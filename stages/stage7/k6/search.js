import http from 'k6/http';
import { check, fail } from 'k6';
import { Counter, Rate } from 'k6/metrics';

export const cacheHits = new Counter('cache_hits');
export const cacheMisses = new Counter('cache_misses');
export const cacheHitRate = new Rate('cache_hit_rate');
const BASE_URL = (__ENV.BASE_URL || 'https://search.apollo.local').replace(/\/$/, '');
const EXPECT_CACHE = __ENV.EXPECT_CACHE || 'on';
const DATE = __ENV.SEARCH_DATE || new Date().toISOString().split('T')[0];
// Every route is seeded. Iteration order is deterministic across both runs.
const ROUTES = [
  ['BOM', 'SIN'], ['SIN', 'BOM'], ['DEL', 'DXB'],
  ['DXB', 'DEL'], ['BOM', 'LHR'], ['DEL', 'JFK'],
];
export const options = {
  scenarios: {
    search: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 50), timeUnit: '1s',
      duration: __ENV.DURATION || '2m',
      preAllocatedVUs: 20, maxVUs: 100,
    },
  },
  thresholds: {
    checks: ['rate==1'], http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<200'], dropped_iterations: ['count==0'],
    cache_hit_rate: EXPECT_CACHE === 'off' ? ['rate==0'] : ['rate>0.9'],
  },
};
function request(route) {
  return http.get(`${BASE_URL}/api/search?origin=${route[0]}&destination=${route[1]}&date=${DATE}`, {
    headers: { Host: 'search.apollo.local', Accept: 'application/json' },
  });
}
function valid(res) {
  try {
    const body = res.json();
    return res.status === 200 && Array.isArray(body.results) && body.results.length > 0 && body.total > 0;
  } catch (_) { return false; }
}
export function setup() {
  if (!['on', 'off'].includes(EXPECT_CACHE)) fail('EXPECT_CACHE must be on or off');
  // Warm the same six keys in each run; this traffic is excluded from latency thresholds.
  for (const route of ROUTES) {
    if (!valid(request(route))) fail(`No seeded results for ${route.join(' -> ')} on ${DATE}; reseed or set SEARCH_DATE`);
  }
}
export default function () {
  const res = request(ROUTES[(__VU + __ITER) % ROUTES.length]);
  const state = res.headers['X-Cache'];
  check(res, {
    'returns seeded flights': valid,
    'reports cache state': () => state === 'HIT' || state === 'MISS',
    'cache bypass gives MISS': () => EXPECT_CACHE !== 'off' || state === 'MISS',
  });
  cacheHitRate.add(state === 'HIT');
  if (state === 'HIT') cacheHits.add(1);
  if (state === 'MISS') cacheMisses.add(1);
}
