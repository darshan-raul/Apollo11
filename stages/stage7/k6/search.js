import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics to observe cache behavior
export const cacheHits = new Counter('cache_hits');
export const cacheMisses = new Counter('cache_misses');
export const cacheHitRate = new Rate('cache_hit_rate');
export const searchDuration = new Trend('search_duration_ms');

export const options = {
  stages: [
    { duration: '10s', target: 10 }, // Ramp up to 10 virtual users
    { duration: '30s', target: 20 }, // Sustain 20 virtual users
    { duration: '10s', target: 0 },  // Ramp down to 0
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],    // Less than 1% failure
    http_req_duration: ['p(95)<200'],  // 95% of requests should be below 200ms
  },
};

const TARGET_HOST = __ENV.TARGET_HOST || 'search.apollo.local';
const TARGET_PORT = __ENV.TARGET_PORT || '';
const BASE_URL = TARGET_PORT ? `http://${TARGET_HOST}:${TARGET_PORT}` : `http://${TARGET_HOST}`;

// Sample search criteria across seeded airports
const ROUTES = [
  { origin: 'BOM', destination: 'DEL' },
  { origin: 'BOM', destination: 'SIN' },
  { origin: 'DEL', destination: 'DXB' },
  { origin: 'LHR', destination: 'JFK' },
  { origin: 'DXB', destination: 'LHR' },
];

export default function () {
  const route = ROUTES[Math.floor(Math.random() * ROUTES.length)];
  const today = new Date().toISOString().split('T')[0];
  const url = `${BASE_URL}/api/search?origin=${route.origin}&destination=${route.destination}&date=${today}`;

  const params = {
    headers: {
      'Host': 'search.apollo.local',
      'Accept': 'application/json',
    },
  };

  const res = http.get(url, params);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has valid response': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body !== null;
      } catch (e) {
        return false;
      }
    },
  });

  const cacheHeader = res.headers['X-Cache'] || res.headers['x-cache'];
  if (cacheHeader === 'HIT') {
    cacheHits.add(1);
    cacheHitRate.add(true);
  } else if (cacheHeader === 'MISS') {
    cacheMisses.add(1);
    cacheHitRate.add(false);
  }

  searchDuration.add(res.timings.duration);
  sleep(0.1);
}
