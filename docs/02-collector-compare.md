# 02. 컬렉터 비교 결과

> 상태: **미실행**. 각 행은 `scripts/summarize-gc.sh --all` 이 출력하는 "비교표 행" 과 k6 요약(RPS, p99)을 옮겨 적는다.
> 실행하지 못한 조합은 빈칸 대신 "미실행" 으로 남긴다.

## 실행 환경

| 항목 | 값 |
|---|---|
| JDK (`java -version`) | (results/*/*/java-version.txt) |
| 머신 | (results/*/*/machine.txt) |
| 힙 | `-Xms1g -Xmx1g` |
| 부하 | k6, VU 50, 3분, 목록 70 / 상세 20 / 작성 10 |
| 더미 데이터 | 1만 건, 본문 1~4KB |

## 비교표

| 컬렉터 | 프로필 | RPS | p99 응답(ms) | GC 정지 횟수 | 최대 정지(ms) | 평균 정지(ms) | 총 정지(ms) | 비고 |
|---|---|---|---|---|---|---|---|---|
| g1 | default | 미실행 | | | | | | |
| shenandoah | default | 미실행 | | | | | | |
| zgc | default | 미실행 | | | | | | |
| zgc-gen | default | 미실행 | | | | | | |
| g1 | leak-static | 미실행 | | | | | | |
| shenandoah | leak-static | 미실행 | | | | | | |
| zgc | leak-static | 미실행 | | | | | | |
| zgc-gen | leak-static | 미실행 | | | | | | |
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
- 단계별 정지 분포 (`Pause Young (Normal)` / `(Concurrent Start)` / `(Mixed)` / `Remark` / `Cleanup`):
- 누수 프로필에서 Mixed GC 정지 변화:
- `MAX_PAUSE=50 scripts/run.sh g1` 로 재실행 시 CSet 크기·GC 빈도 변화: (미실행)

### 셰넌도어
- Pause 항목이 전부 1ms 안팎인가:
- 누수로 힙이 차도 Pause 길이가 그대로인가:
- Concurrent 구간 총 시간·CPU:
- Degenerated / Full GC 발생 여부, `[gc,stats]` Pacing 합계:

### ZGC / 세대 구분 ZGC
- Pause 세 개 모두 1ms 미만인가:
- Allocation Stall 발생 여부:
- zgc vs zgc-gen: GC 주기 횟수, CPU 사용 차이:

## 가설 검증

| # | 가설 | 판정 | 근거 |
|---|---|---|---|
| 1 | 스프링 빈은 GC 루트가 아니다 | 미확인 | docs/01 의 PostService 경로 |
| 2 | 요청 중 DTO·엔티티는 Java Local 에만 매달리고 에덴에서 죽는다 | 미확인 | docs/01 의 Post 경로, 히스토그램의 Post 개수 |
| 3 | 누수 시 Post 의 루트 경로가 Java Local → System Class / Thread 로 바뀐다 | 미확인 | docs/03 |
| 4 | G1 은 이동 단계에서 가장 길게 멈추고, 셰넌도어·ZGC 는 1ms 안팎. RPS 는 G1 이 최고 | 미확인 | 위 비교표 default 행 |
| 5 | 누수로 구세대가 커질수록 G1 Mixed 정지는 길어지지만 셰넌도어·ZGC 정지는 거의 그대로 | 미확인 | default vs leak-* 행 |

## 추가 실험 (여유가 있으면)

- `HEAP=4g BOARD_SEED_COUNT=100000 scripts/run.sh g1` 로 힙을 키웠을 때 G1 정지 시간 증가 확인: (미실행)
