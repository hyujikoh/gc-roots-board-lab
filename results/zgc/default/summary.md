# zgc (비세대) / default — 실행 기록 (2026-09-21)

## 조건
- `scripts/run-docker.sh zgc` — Docker `--cpus=2 --memory=2g`, 힙 1g 고정, Temurin 21.0.12+8, `-XX:+UseZGC`
- JVM 이 본 리소스: CPU 2 → `ParallelGCThreads=2`, `ConcGCThreads=1`
- 부하: k6 VU 50, 3분, SLEEP=0
- gc.log 수명: 266초

## k6 결과
| RPS | p50 | p99 | max | 실패 |
|---|---|---|---|---|
| (k6 요약 미기록) | | | | |

## gc.log 요약
| 항목 | 값 |
|---|---|
| GC 주기 | 672회 — 트리거: Allocation Stall 638, Allocation Rate 28, Warmup 3, Proactive 1, Metadata 2 |
| GC 정지 횟수 | 2016 (주기당 Mark Start / Mark End / Relocate Start) |
| 최대 정지 | 2.04ms (Pause Mark Start) |
| 평균 정지 | 0.035ms |
| 총 정지 | 71.4ms |
| safepoint 총 / 최대 | 7895ms (2135회) / 383ms (XRelocateStart) |
| safepoint 내역 | 도달 대기 총 7447ms (최대 382ms), 정지 중 총 314ms (최대 97ms) |
| **Allocation Stall** | **24,649회, 합계 1,835초, 평균 74.5ms, 최대 1,024ms** |
| Concurrent Mark 평균 | 113ms (672회) |
| Concurrent Relocate 평균 | 5ms |
| 마지막 MMU | 10ms 창 79.6%, 100ms 창 98.0% |

## 관찰
- Pause 이벤트 자체는 모두 2ms 미만, 평균 35µs. "정지는 힙 크기와 무관하게 짧다" 는 그대로 확인됨.
- 그러나 주기 672회 중 638회가 **Allocation Stall 로 트리거**. 즉 GC 가 할당을 못 따라가 요청 스레드가 메모리를 받을 때까지 멈춘 것. 스레드별 정지 합계 1,835초 = 3분 부하 동안 50개 VU 요청 스레드가 평균 60% 시간을 할당 대기로 보냈다는 뜻. 최대 1초 정지.
- 이것이 책의 "ZGC 의 대가: 할당 속도 한계". 2코어에 ConcGCThreads=1 이면 동시 표시(113ms)가 에덴이 차는 속도(수백 ms)를 못 이긴다.
- safepoint 도달 대기 7.4초 — 셰넌도어와 같은 구조(2코어 + 100 스레드). Pause 이벤트 시간과 safepoint Total 의 차이가 100배.
