// Optional k6 smoke/load test for an isolated staging deployment.
// Never point this at production. Set STAGING_BASE_URL and STAGING_ANON_KEY.
// Authentication must use a dedicated staging test account; never paste a
// production service-role key into this script.
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    asset_register_readers: {
      executor: 'constant-vus',
      vus: 50,
      duration: '2m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1500'],
  },
};

const base = __ENV.STAGING_BASE_URL;
const anon = __ENV.STAGING_ANON_KEY;
const token = __ENV.STAGING_USER_ACCESS_TOKEN;
if (!base || !anon || !token) {
  throw new Error('Set STAGING_BASE_URL, STAGING_ANON_KEY and STAGING_USER_ACCESS_TOKEN');
}

export default function () {
  const response = http.get(
    base + '/rest/v1/assets?select=id,asset_code,name,operational_status&order=asset_code.asc&limit=25',
    { headers: { apikey: anon, Authorization: 'Bearer ' + token } },
  );
  check(response, {
    'status is 200': r => r.status === 200,
    'response is JSON': r => (r.headers['Content-Type'] || '').includes('application/json'),
  });
  sleep(1);
}
