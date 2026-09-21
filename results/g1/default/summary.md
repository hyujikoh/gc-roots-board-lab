# g1 / default — 실행 기록 (2026-09-21)

## 조건
- 실행: `scripts/run-docker.sh g1` — Docker Desktop(Linux aarch64 VM), `--cpus=2 --memory=2g`, 힙 `-Xms1g -Xmx1g`, `-XX:MaxGCPauseMillis=200`
- JDK: Temurin 21.0.12+8 (eclipse-temurin:21 이미지)
- JVM 이 본 리소스: Effective CPU Count 2, Memory Limit 2G → `ParallelGCThreads=2`, `ConcGCThreads=1`
- 호스트: Apple M4 10코어 / 32GB
- 부하: `k6 run load/board.js` — VU 50, 3분, SLEEP=0(닫힌 루프), 목록 70 / 상세 20 / 작성 10
- 더미 데이터: 1만 건, 본문 1~4KB. 부하 중 작성으로 +72,737건

## k6 결과
| RPS | p50 | p90 | p99 | max | 실패 | 총 요청 |
|---|---|---|---|---|---|---|
| 4062.1 | 3.4ms | 62.4ms | 88.5ms | 1798.9ms | 0.00% | 731,810 |

## gc.log 요약 (`scripts/summarize-gc.sh`, jcmd 유발 Full GC 2회 제외)
gc.log 는 서버 수명 전체(약 22분, 부하 전 유휴 ~10분 포함)를 담고 있다. 부하 구간은 uptime 약 587~770초.

| 항목 | 값 |
|---|---|
| GC 정지 횟수 | 979 |
| 최대 정지 | 134.1ms — `Pause Young (Prepare Mixed) 394M->63M` (부하 시작 직후 첫 GC) |
| 평균 정지 | 4.8ms |
| 총 정지 | 4703.8ms |
| safepoint 총/최대 | 13196ms (1293회) / 330ms (HeapDumper — 부하 종료 후 덤프 시점) |
| Full GC (부하 중) | 0 |
| Evacuation Failure | 0 |
| 제외한 도구 유발 Full GC | 2회 210.9ms (`Heap Inspection Initiated`, `Heap Dump Initiated` — 부하 종료 후 dump.sh 가 유발) |

종류별

| 정지 종류 | 횟수 | 최대(ms) | 평균(ms) | 총(ms) |
|---|---|---|---|---|
| Pause Young (Normal) | 254 | 73.5 | 5.4 | 1364.8 |
| Pause Young (Concurrent Start) | 142 (+3 Metadata/GCLocker) | 80.5 | 5.5 | 794.5 |
| Pause Remark | 145 | 72.4 | 6.4 | 930.1 |
| Pause Cleanup | 145 | 0.9 | 0.25 | 36.5 |
| Pause Young (Prepare Mixed) | 144 (+1) | 134.1 | 5.4 | 789.8 |
| Pause Young (Mixed) | 143 (+2) | 73.4 | 5.4 | 788.0 |

## 관찰
- G1 한 주기(Concurrent Start → Concurrent Mark Cycle → Remark → Cleanup → Prepare Mixed → Mixed)가 부하 3분 동안 145번 돌았다. 동시 표시 1회 평균 392ms(ConcGCThreads=1).
- Young GC 는 100~200ms 마다 발생 (Eden 599 리전≈599MB 가 그 사이 다 참). 할당 속도가 초당 수 GB 수준. 목록 응답이 CLOB 본문 20건을 매번 로드하는 구조 때문.
- 한 Young GC 의 정지는 거의 전부 `Evacuate Collection Set`(예: GC(300) 63.1ms 중 61.8ms). `Merge Heap Roots`(기억 집합 처리)는 0.1ms 미만.
- 같은 크기의 Young GC 가 3ms 로 끝나기도, 60~80ms 걸리기도 한다. 2코어를 톰캣 워커 100개와 GC 스레드 2개가 나눠 쓰면서 GC 스레드가 CPU 를 못 받는 순간이 있음. 코어 제한이 정지 시간 분산으로 나타난다.
- 부하 종료 시점 구세대 262 리전(≈262MB): H2 인메모리 테이블(초기 1만 + 작성 7.3만 건)이 대부분. 히스토그램 1위 `[B` 225MB 가 그것.
- 히스토그램(부하 종료 후, 도달 가능 객체만)에 `Post` 인스턴스가 상위 20에 없음 → 가설 2 와 부합하는 첫 신호. 확정은 MAT 의 Path to GC Roots 로.
