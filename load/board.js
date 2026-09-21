// k6 부하 스크립트: 목록 70% / 상세 20% / 작성 10%, 가상 사용자 50명, 3분
//
//   k6 run load/board.js
//   k6 run -e VUS=50 -e DURATION=3m -e BASE=http://localhost:8080 load/board.js
//   k6 run --summary-export results/g1/default/k6.json load/board.js   # 수치 파일로 저장
//
// 결과에서 기록할 것: http_reqs (RPS), http_req_duration p(50) / p(99) / max

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE = __ENV.BASE || 'http://localhost:8080';
const VUS = Number(__ENV.VUS || 50);
const DURATION = __ENV.DURATION || '3m';
const PAGE_SIZE = 20;

export const options = {
  scenarios: {
    board: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
  // 요약에 p99·max 가 반드시 나오도록
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(99)', 'max'],
};

const listDuration = new Trend('list_duration', true);
const viewDuration = new Trend('view_duration', true);
const createDuration = new Trend('create_duration', true);
const created = new Counter('posts_created');

// 상세 조회용 id 범위. setup 에서 한 번 조회해 모든 VU 가 공유한다.
export function setup() {
  const res = http.get(`${BASE}/posts/count`);
  const count = res.json('count');
  if (!count || count < 1) {
    throw new Error(`서버에 게시글이 없습니다 (${BASE}/posts/count -> ${res.body})`);
  }
  return { maxId: count };
}

function randomBody() {
  // 1~4KB. 서버의 더미 데이터와 같은 크기 분포로 작성 요청도 할당 압력을 만든다.
  const len = 1024 + Math.floor(Math.random() * 3072);
  let s = '';
  const chunk = 'lorem ipsum dolor sit amet consectetur adipiscing elit ';
  while (s.length < len) s += chunk;
  return s.slice(0, len);
}

export default function (data) {
  const r = Math.random();
  if (r < 0.7) {
    // 목록: 앞쪽 페이지에 몰리게 (실제 게시판 접근 패턴)
    const page = Math.floor(Math.random() * 50);
    const res = http.get(`${BASE}/posts?page=${page}&size=${PAGE_SIZE}`, { tags: { name: 'list' } });
    listDuration.add(res.timings.duration);
    check(res, { 'list 200': (x) => x.status === 200 });
  } else if (r < 0.9) {
    const id = 1 + Math.floor(Math.random() * data.maxId);
    const res = http.get(`${BASE}/posts/${id}`, { tags: { name: 'view' } });
    viewDuration.add(res.timings.duration);
    check(res, { 'view 200': (x) => x.status === 200 });
  } else {
    const payload = JSON.stringify({
      title: `k6-${__VU}-${__ITER}`,
      content: randomBody(),
      author: `vu-${__VU}`,
    });
    const res = http.post(`${BASE}/posts`, payload, {
      headers: { 'Content-Type': 'application/json' },
      tags: { name: 'create' },
    });
    createDuration.add(res.timings.duration);
    if (check(res, { 'create 201': (x) => x.status === 201 })) created.add(1);
  }
  // 생각 시간 없이 계속 때리면 로컬 노트북에서는 CPU 가 먼저 바닥난다. 짧게 쉰다.
  sleep(0.05);
}

export function handleSummary(data) {
  const m = data.metrics;
  const d = m.http_req_duration.values;
  const line = [
    `RPS=${(m.http_reqs.values.rate).toFixed(1)}`,
    `p50=${d.med.toFixed(1)}ms`,
    `p99=${d['p(99)'].toFixed(1)}ms`,
    `max=${d.max.toFixed(1)}ms`,
    `failed=${(m.http_req_failed.values.rate * 100).toFixed(2)}%`,
    `reqs=${m.http_reqs.values.count}`,
  ].join('  ');
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }) + `\n==== 비교표용 요약 ====\n${line}\n\n`,
  };
}
