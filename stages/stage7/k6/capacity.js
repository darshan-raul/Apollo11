import http from 'k6/http';
import {check, fail} from 'k6';
const base = (__ENV.BASE_URL || 'https://search.apollo.local').replace(/\/$/, '');
const date = __ENV.SEARCH_DATE || new Date().toISOString().split('T')[0];
export const options = {
  scenarios: {capacity: {executor: 'ramping-arrival-rate', startRate: 10, timeUnit: '1s',
    preAllocatedVUs: 30, maxVUs: 200,
    stages: [{target: 50, duration: '2m'}, {target: 100, duration: '3m'},
      {target: 200, duration: '3m'}, {target: 10, duration: '6m'}]}},
  thresholds: {checks: ['rate==1'], http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<200'], dropped_iterations: ['count==0']},
};
function request() { return http.get(`${base}/api/search?origin=BOM&destination=SIN&date=${date}`); }
function valid(r) { try {return r.status === 200 && r.json().results.length > 0;} catch (_) {return false;} }
export function setup() { if (!valid(request())) fail('No seeded flights at target'); }
export default function () { check(request(), {'real flight response': valid}); }
