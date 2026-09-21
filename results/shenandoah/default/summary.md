# shenandoah / default — 실행 기록 (2026-09-21)

## 조건
- `scripts/run-docker.sh shenandoah` — Docker `--cpus=2 --memory=2g`, 힙 1g 고정, Temurin 21.0.12+8
- JVM 이 본 리소스: CPU 2, Memory 2G → `ParallelGCThreads=1`, `ConcGCThreads=1`
- 부하: k6 VU 50, 3분, SLEEP=0 (g1 과 동일)
- gc.log 수명: 221초 (부하 3분 + 기동/종료)

## k6 결과
| RPS | p50 | p99 | max | 실패 |
|---|---|---|---|---|
| (k6 요약 미기록) | | | | |

## gc.log 요약 (`scripts/summarize-gc.sh`)
| 항목 | 값 |
|---|---|
| GC 주기 | 845회 (전부 successful concurrent, Degenerated 0, Full 0) |
| GC 정지 횟수 | 3380 (주기당 4개: Init Mark / Final Mark / Init Update Refs / Final Update Refs) |
| 최대 정지 | 56.3ms (Pause Final Update Refs) |
| 평균 정지 | 0.212ms |
| 총 정지 | 718.1ms |
| safepoint 총 / 최대 | 9356ms (3577회) / 210ms |
| safepoint 내역 | 도달 대기(Reaching) 총 8180ms, 정지 중(At safepoint) 총 844ms |

종류별 (Net = 순수 GC 작업, Gross = 도달 대기 포함, `[gc,stats]` 기준)

| 정지 | 횟수 | Net 평균 | Net 최대 | Gross 평균 | Gross 최대 |
|---|---|---|---|---|---|
| Pause Init Mark | 845 | 0.18ms | 41ms | 3.4ms | 180ms |
| Pause Final Mark | 845 | 0.32ms | 30ms | 1.1ms | 93ms |
| Pause Init Update Refs | 845 | 0.16ms | 30ms | 3.7ms | 902ms |
| Pause Final Update Refs | 845 | 0.30ms | 56ms | 5.0ms | 203ms |

동시 단계 (`[gc,stats]`)

| 단계 | 총 | 평균 |
|---|---|---|
| Concurrent Marking | 42.6s | 50ms |
| Concurrent Update Refs | 47.4s | 56ms |
| Concurrent Class Unloading | 16.0s | 19ms |
| Concurrent Weak Roots | 9.8s | 11.6ms |
| Concurrent Evacuation | 2.9s | 3.5ms |
| **Pacing (할당 스레드 지연 합계)** | **988s** | 주기당 1.17s (p90 1.4s, 최대 4.8s) |

## 관찰
- 정지의 중앙값은 0.1~0.3ms 로 "1ms 안팎" 이라는 예상에 부합. 그러나 최대는 30~56ms 까지 튐. 원인은 GC 작업량이 아니라 2코어에서 100개 톰캣 스레드를 safepoint 에 세우는 시간(Gross − Net). safepoint 총 9.4초 중 8.2초가 도달 대기.
- Degenerated / Full GC 는 0 이지만 대신 Pacing 이 988초. 할당이 GC 를 앞지르자 셰넌도어가 할당 스레드를 재우며(pacer) 버틴 것. 요청 스레드 관점에서는 이게 곧 응답 지연이며, 로그의 "Pause" 에는 잡히지 않는다.
- 주기 845회/3분 ≈ 초당 4.7회. 세대 구분이 없어 매 주기 힙 전체(H2 테이블 200MB+ 포함)를 표시·참조 갱신. Marking + Update Refs 가 동시 작업의 대부분.
- ParallelGCThreads=1 (G1 은 2). 셰넌도어는 2코어 환경에서 정지 작업을 1스레드로 함.
