# zgc-gen (세대 구분) / default — 실행 기록 (2026-09-21)

## 조건
- `scripts/run-docker.sh zgc-gen` — Docker `--cpus=2 --memory=2g`, 힙 1g 고정, Temurin 21.0.12+8, `-XX:+UseZGC -XX:+ZGenerational`
- JVM 이 본 리소스: CPU 2 → `ParallelGCThreads=2`, `ConcGCThreads=1`
- 부하: k6 VU 50, 3분, SLEEP=0
- gc.log 수명: 415초 (부하 전후 유휴 포함)

## k6 결과
| RPS | p50 | p99 | max | 실패 |
|---|---|---|---|---|
| (k6 요약 미기록) | | | | |

## gc.log 요약
| 항목 | 값 |
|---|---|
| GC 주기 | Minor 631회 (트리거 Allocation Rate 573, Allocation Stall 58) + Major 35회 (Allocation Rate 29, Warmup 3, Metadata 2, Proactive 1) |
| GC 정지 횟수 | 2068 (Minor 631×3 + Major 35×5). 처음 summarize 가 175 로 낸 것은 Minor 의 소문자 `y:` 접두를 못 잡은 버그 — 수정함 |
| 최대 정지 | 0.345ms (y: Pause Mark Start) |
| 평균 정지 | 0.012ms |
| 총 정지 | 25.3ms |
| safepoint 총 / 최대 | 17,895ms (2315회) / 306ms (ZMarkEndOld) |
| safepoint 내역 | 도달 대기 총 17,078ms (최대 295ms), 정지 중 총 417ms (최대 109ms) |
| **Allocation Stall** | **12,994회, 합계 158초, 평균 12.2ms, 최대 160ms** |
| y: Concurrent Mark 평균 (Minor) | 15ms 대 |
| Y: Concurrent Mark 평균 (Major) | 97ms |
| O: Concurrent Mark 평균 (Major) | 428ms (35회) |

## 관찰
- 비세대 ZGC 대비 Allocation Stall 합계 1,835초 → 158초 (1/11.6), 평균 74.5ms → 12.2ms, 최대 1,024ms → 160ms. 세대 구분이 "할당 속도 한계" 를 크게 완화함. 신세대만 자주(631회) 훑고 구세대(H2 테이블) 는 35회만.
- 트리거도 Allocation Stall(58) 보다 Allocation Rate(573) 가 압도적 — 대부분 "미리" 시작해 제때 끝냈다는 뜻.
- 단, safepoint 도달 대기가 17초로 넷 중 가장 큼. Minor 주기가 잦아 safepoint 횟수(2315)가 많고, 2코어에서 100 스레드를 세우는 비용이 그때마다 든다.
- Pause 이벤트는 모두 0.35ms 이하, 평균 12µs.
