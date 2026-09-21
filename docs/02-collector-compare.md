# 02. 컬렉터 비교 결과

> 상태: **진행 중** (default 4종 + leak-static 4종 GC 로그 기록 완료. k6 RPS·p99 는 g1/default 외 미기록. leak-threadlocal / leak-listener 미실행). 각 행은 `scripts/summarize-gc.sh --all` 이 출력하는 "비교표 행" 과 k6 요약(RPS, p99)을 옮겨 적는다.
> 실행하지 못한 조합은 빈칸 대신 "미실행" 으로 남긴다.

## 실행 환경

| 항목 | 값 |
|---|---|
| JDK (`java -version`) | Temurin 21.0.12+8 (eclipse-temurin:21) |
| 머신 | Docker Desktop(Linux aarch64 VM) `--cpus=2 --memory=2g`, 호스트 Apple M4 10코어/32GB |
| 힙 | `-Xms1g -Xmx1g` |
| 부하 | k6, VU 50, 3분, SLEEP=0, 목록 70 / 상세 20 / 작성 10 |
| 더미 데이터 | 1만 건, 본문 1~4KB |

## 비교표

| 컬렉터 | 프로필 | RPS | p99 응답(ms) | GC 정지 횟수 | 최대 정지(ms) | 평균 정지(ms) | 총 정지(ms) | 비고 |
|---|---|---|---|---|---|---|---|---|
| g1 | default | 4062.1 | 88.5 | 979 | 134.1 | 4.8 | 4703.8 | Docker 2코어/2GB. safepoint 총 13196ms. 상세: results/g1/default/summary.md |
| shenandoah | default | (미기록) | (미기록) | 3380 | 56.3 | 0.21 | 718.1 | safepoint 총 9356ms(도달 대기 8180). **Pacing 988s**. Degenerated 0. 상세: results/shenandoah/default/summary.md |
| zgc | default | (미기록) | (미기록) | 2016 | 2.04 | 0.035 | 71.4 | safepoint 총 7895ms. **Allocation Stall 24,649회 합계 1,835s, 최대 1,024ms**. 주기 672회 중 638회가 Stall 트리거. 상세: results/zgc/default/summary.md |
| zgc-gen | default | (미기록) | (미기록) | 2068 | 0.35 | 0.012 | 25.3 | safepoint 총 17,895ms(도달 대기 17,078). Allocation Stall 12,994회 합계 158s, 최대 160ms. Minor 631 / Major 35. 상세: results/zgc-gen/default/summary.md |
| g1 | leak-static | (미기록) | (미기록) | 1028 | 78.9 | 5.5 | 5684.0 | 구세대 2→635 리전(default 는 262). Mixed 평균 5.4→8.5ms, 분 단위로 7.5→9.0ms 증가. Full/이주 실패 0 |
| shenandoah | leak-static | (미기록) | (미기록) | 3118 | 131.0 | 0.31 | 975.1 | **Degenerated GC 5회** (Outside of Cycle 2회 최대 131ms, Evacuation 2회, Mark 1회). Pacing 1,364s (default 988s). 주기 785회, Concurrent marking 평균 50→69ms. (부하 중 summarize 는 로그가 다 안 써져 2290/1회로 나왔음 — 종료 후 값이 이것) |
| zgc | leak-static | (미기록) | (미기록) | 2010 | 1.11 | 0.034 | 67.9 | Pause 는 default 와 동일. **Allocation Stall 24,668회 합계 2,422s(default 1,835s), 평균 98ms(74ms), 최대 1,024ms**. 주기 670회 중 644회 Stall 트리거. 종료 시 힙 점유 63% |
| zgc-gen | leak-static | (미기록) | (미기록) | 2462 | 0.30 | 0.011 | 27.2 | Pause 는 default 와 동일. Allocation Stall 23,162회 합계 307s(default 158s, ×1.9), 평균 13ms, 최대 267ms(160ms). Minor 749(Stall 트리거 58→174) / Major 43. 종료 시 힙 점유 84~90% |
| g1 | leak-threadlocal | 미실행 | | | | | | |
| shenandoah | leak-threadlocal | 미실행 | | | | | | |
| zgc | leak-threadlocal | 미실행 | | | | | | |
| zgc-gen | leak-threadlocal | 미실행 | | | | | | |
| g1 | leak-listener | 미실행 | | | | | | |
| shenandoah | leak-listener | 미실행 | | | | | | |
| zgc | leak-listener | 미실행 | | | | | | |
| zgc-gen | leak-listener | 미실행 | | | | | | |

"최대/평균/총 정지" 는 GC 로그의 `Pause ...` 이벤트 기준이다. safepoint 기준 값(도달 대기 포함)은 summarize 출력의 `safepoint 총 시간 / 최대` 를 비고에 함께 적는다.
ZGC 는 Pause 이벤트 시간(수십 µs)과 safepoint Total(수 ms) 차이가 클 수 있다. 전자는 GC 가 멈춰서 한 일, 후자는 모든 스레드를 세우는 데 든 시간까지 포함한다.

## 컬렉터별 로그 관찰

### G1
- 단계별 정지 분포 (`Pause Young (Normal)` / `(Concurrent Start)` / `(Mixed)` / `Remark` / `Cleanup`): default 기준 Normal 254회 평균 5.4ms / Concurrent Start 142회 5.5ms / Remark 145회 6.4ms(최대 72ms) / Cleanup 145회 0.25ms / Prepare Mixed 144회 5.4ms(최대 134ms) / Mixed 143회 5.4ms. 주기 145회, 동시 표시 평균 392ms. 정지의 대부분은 Evacuate Collection Set. 2코어라 같은 크기 GC 가 3ms~80ms 로 분산.
- 누수 프로필에서 Mixed GC 정지 변화: leak-static 에서 구세대가 262→635 리전으로 커지자 Mixed 평균 5.4→8.5ms(+57%), 총 777→1222ms. 분 단위 평균 7.5→7.7→9.0ms 로 누수 누적에 따라 증가. Normal Young 도 5.4→5.8ms. 최대 정지는 오히려 134→79ms 로 줄었는데 default 의 134ms 는 부하 시작 직후 1회성.
- `MAX_PAUSE=50 scripts/run.sh g1` 로 재실행 시 CSet 크기·GC 빈도 변화: (미실행)

### 셰넌도어
- Pause 항목이 전부 1ms 안팎인가: **Net 은 그렇다** (Init Mark 0.18ms / Final Mark 0.32ms / Init UR 0.16ms / Final UR 0.30ms 평균). 그러나 최대는 30~56ms, Gross(도달 대기 포함) 최대 902ms. 정지 시간의 지배 요인이 GC 작업이 아니라 2코어에서 100 스레드를 safepoint 에 세우는 시간.
- 누수로 힙이 차도 Pause 길이가 그대로인가: **정상 주기의 Pause 는 그대로**(Init Mark 0.12ms / Final Mark 0.33ms / Init UR 0.14ms 평균). 그러나 힙이 970MB 까지 차자 **Degenerated GC 5회**(최대 131ms) 발생 — 동시 주기가 할당을 못 따라가 STW 로 전환된 것. Pacing 도 988→1,364s 로 증가.
- Concurrent 구간 총 시간·CPU: Marking 42.6s + Update Refs 47.4s + Class Unloading 16.0s + Weak Roots 9.8s (3분 부하 동안, ConcGCThreads=1). 주기 845회 = 초당 4.7회.
- Degenerated / Full GC 발생 여부, `[gc,stats]` Pacing 합계: Degenerated 0, Full 0. **Pacing 988s** (주기당 평균 1.17s, 최대 4.8s) — 할당 스레드를 재워서 버텼다. Pause 로그에는 안 보이지만 응답 지연으로는 나타난다.

### ZGC / 세대 구분 ZGC
- Pause 세 개 모두 1ms 미만인가: zgc 는 최대 2.04ms(Mark Start 1회), 나머지 전부 1ms 미만, 평균 35µs. zgc-gen 은 최대 0.35ms, 평균 12µs. **정지 자체는 예상대로.**
- Allocation Stall 발생 여부: **zgc 24,649회 합계 1,835s(평균 74.5ms, 최대 1,024ms)**, 주기 672회 중 638회가 Stall 로 트리거 — GC 가 할당을 전혀 못 따라감. **zgc-gen 12,994회 합계 158s(평균 12.2ms, 최대 160ms)**, 트리거 대부분 Allocation Rate(선제) — 1/11.6 로 줄었지만 여전히 있음.
- 누수(leak-static)에서: 두 ZGC 모두 Pause 는 변화 없음. 대신 Stall 이 zgc 1,835→2,422s, zgc-gen 158→307s 로 증가. zgc-gen 은 Minor 트리거 중 Stall 비율이 58/631 → 174/749 로 3배. 구세대(누수 맵)가 커질수록 Major 가 길어지고(O: Concurrent Mark) 그 사이 신세대가 차서 Stall.
- zgc vs zgc-gen: 비세대 672주기(매번 힙 전체 표시, Concurrent Mark 평균 113ms) vs 세대 Minor 631 + Major 35 (Minor Concurrent Mark 15ms 대). 세대 구분이 "할당 속도 한계" 를 크게 완화. 단 safepoint 도달 대기는 zgc-gen 이 17s 로 넷 중 최대 (safepoint 횟수 2315).

## 가설 검증

| # | 가설 | 판정 | 근거 |
|---|---|---|---|
| 1 | 스프링 빈은 GC 루트가 아니다 | 미확인 | docs/01 의 PostService 경로 |
| 2 | 요청 중 DTO·엔티티는 Java Local 에만 매달리고 에덴에서 죽는다 | 미확인 | docs/01 의 Post 경로, 히스토그램의 Post 개수 |
| 3 | 누수 시 Post 의 루트 경로가 Java Local → System Class / Thread 로 바뀐다 | 미확인 | docs/03 |
| 4 | G1 은 이동 단계에서 가장 길게 멈추고, 셰넌도어·ZGC 는 1ms 안팎. RPS 는 G1 이 최고 | **정지 부분 맞음 / RPS 부분 미확인** | 정지: G1 최대 134ms·평균 4.8ms(Evacuate 가 대부분) vs 셰넌도어 평균 0.21ms, zgc 0.035ms, zgc-gen 0.012ms. 단 2코어 환경에서는 (a) safepoint 도달 대기(셰넌도어 8.2s, zgc 7.4s, zgc-gen 17s) 와 (b) 저지연 컬렉터의 할당 대기(셰넌도어 Pacing 988s, zgc Stall 1,835s) 가 Pause 보다 훨씬 큰 지연 요인. "정지 1ms" 가 "응답 지연 1ms" 를 뜻하지 않는다. RPS 는 셰넌도어/ZGC 의 k6 요약 미기록으로 판정 보류 |
| 5 | 누수로 구세대가 커질수록 G1 Mixed 정지는 길어지지만 셰넌도어·ZGC 정지는 거의 그대로 | **맞음 — 단, "정지" 를 Pause 로 한정할 때만** | G1: Mixed 평균 5.4→8.5ms, 시간 경과에 따라 증가. 셰넌도어: 정상 Pause 0.1~0.3ms 그대로이나 Degenerated GC 5회(최대 131ms). ZGC: Pause 평균 0.034ms(그대로), 최대 2.0→1.1ms. ZGC-gen: Pause 평균 0.011ms(그대로). **그러나 Pause 밖의 비용은 모두 늘었다**: 셰넌도어 Pacing 988→1,364s, ZGC Stall 1,835→2,422s, ZGC-gen Stall 158→307s(×1.9). 저지연 컬렉터는 힙이 차도 "멈추지" 않는 대신 "할당을 재운다" — 응답 지연으로는 똑같이 나타난다 |

## 추가 실험 (여유가 있으면)

- `HEAP=4g BOARD_SEED_COUNT=100000 scripts/run.sh g1` 로 힙을 키웠을 때 G1 정지 시간 증가 확인: (미실행)
