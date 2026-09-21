# BACKLOG

잔여 작업과 그 이력. 상태가 바뀌면 이 파일의 표를 고치고 아래 "이력" 에 한 줄 남긴다.

상태: `todo` 아직 안 함 · `doing` 진행 중 · `done` 끝 · `skip` 안 하기로 함(이유 기록)

## 잔여 작업

| 우선순위 | 작업 | 상태 | 닫히는 가설 | 메모 |
|---|---|---|---|---|
| 1 | **MAT 로 정상 프로필 루트 지도 작성** — `results/g1/default/dump-mid.hprof` 를 Eclipse MAT 로 열어 `Post` → Merge Shortest Paths to GC Roots (exclude weak/soft), `PostService` → Path to GC Roots, GC Roots 뷰의 종류별 개수를 `docs/01-gc-roots.md` 에 기록 | todo | 1, 2 | 덤프는 이미 있음. 30분 작업. 레포 이름값을 하려면 이게 먼저 |
| 2 | **leak-static 덤프 + MAT** — `scripts/run-docker.sh g1 leak-static` → `k6 run -e DURATION=90s load/board.js` → 60초쯤 `scripts/dump.sh g1 leak-static mid` → MAT 에서 `Post` 경로가 `StaticMapLeak.CACHE` 로 끝나는지 확인, `docs/03-leak-scenarios.md` 시나리오 1 기록 | todo | 3 | 비교 실행과 분리해서 별도로 |
| 3 | **Shenandoah / ZGC / ZGC-gen 의 k6 RPS·p99 재측정** — 각각 `k6 run --summary-export results/<c>/default/k6.json load/board.js` 로 다시 돌려 `docs/02` 비교표의 "(미기록)" 채우기 | todo | 4 (RPS 부분) | 첫 실행 때 k6 요약을 복사해 두지 않아 유실. Stall 합계로 방향은 이미 명확해 우선순위 낮음 |
| 4 | leak-threadlocal / leak-listener — g1 으로만 돌려 덤프 + MAT, `docs/03` 시나리오 2·3 | todo | 3 (경로 종류 추가) | 루트 종류가 Thread / ApplicationContext 경유로 바뀌는 것을 보는 용도. 컬렉터 비교엔 영향 없음 |
| 5 | JFR `jdk.OldObjectSample` 로 덤프 없이 같은 경로가 보이는지 교차 확인 — JDK Mission Control 로 `rec.jfr` 열기 | todo | 1, 3 | `path-to-gc-roots=true` 로 녹화돼 있음 |
| 6 | `MAX_PAUSE=50` 으로 G1 재실행 — CSet 크기·GC 빈도 변화 | todo | — | 선택 |
| 7 | `HEAP=4g BOARD_SEED_COUNT=100000` 으로 힙을 키워 G1 정지 증가 확인 | todo | — | 선택. `MEM=8g` 도 같이 |
| 8 | `CPUS=4` 로 한 번 더 — 코어 수가 safepoint 도달 대기·Stall 을 얼마나 줄이는지 | todo | — | 선택. 이번 결론이 "2코어라서" 인지 분리하는 실험 |
| — | 셰넌도어 세대 구분 모드 | skip | — | JDK 21 에 없음 |

## 이력

| 날짜 | 변경 |
|---|---|
| 2026-09-21 | 프로젝트 생성. 게시판 앱, 누수 시나리오 3종, `run.sh` / `dump.sh` / `summarize-gc.sh`, k6 스크립트, docs 템플릿 작성 |
| 2026-09-21 | `run.sh` JDK 21 탐색 보강 (셸 JAVA_HOME 이 17 이어도 brew/sdkman/Temurin 21 을 찾음), macOS bash 3.2 빈 배열 버그 수정, `settings.gradle.kts` 에 foojay toolchain 리졸버 추가 |
| 2026-09-21 | 호스트(M4 10코어)에서 g1 첫 실행. k6 `sleep(0.05)` 때문에 RPS 가 ~940 에 캡되는 문제 발견 → `SLEEP` 환경변수, 기본 0 |
| 2026-09-21 | `Dockerfile` + `run-docker.sh` 추가. 이후 모든 비교는 `--cpus=2 --memory=2g` 컨테이너에서 |
| 2026-09-21 | `jcmd` 히스토그램/덤프가 Full GC 를 강제해 비교를 오염시키는 것 발견 → `dump.sh` `-all=true`, `summarize-gc.sh` 가 도구 유발 Full GC 를 분리 집계 |
| 2026-09-21 | default 프로필 4종 완료. Pause 는 예상대로지만 safepoint 도달 대기·Pacing·Allocation Stall 이 지배적이라는 것 확인 |
| 2026-09-21 | `summarize-gc.sh` 가 세대 ZGC Minor 주기(`y:` 접두)를 못 세던 버그 수정 (175 → 2068회) |
| 2026-09-21 | leak-static 4종 완료. 가설 5 "Pause 기준 맞음, 단 할당 대기 증가" 로 판정 |
| 2026-09-21 | README 를 리포트 형태로 재구성, 그래프 3종(`scripts/charts.py`) 추가, 핸드오프 문서를 `docs/00-handoff.md` 로 이동, 이 파일 신설 |
