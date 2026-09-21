# 원래의 핸드오프 문서

이 레포를 시작할 때 작성한 배경·가설·계획 문서. 현재 상태는 README 와 [BACKLOG.md](BACKLOG.md) 를 본다.

## 1. 배경 (전후 사정)

작성자(오현직, GitHub `hyujikoh`)는 JVM GC를 학습하면서 G1, 셰넌도어, ZGC의 철학과 처리 단계를 노트로 정리했다. 정리한 핵심은 다음과 같다.

| | G1 | 셰넌도어 | ZGC |
|---|---|---|---|
| 철학 | 정지 시간을 예측·제어하면서 처리량 최대화 | 힙 크기와 무관한 짧은 정지 | 힙 크기와 무관한 짧은 정지 |
| 객체 이동 | 사용자 스레드 정지 상태에서 병렬 수행 | 사용자 스레드와 동시 | 사용자 스레드와 동시 |
| 리전 간 참조 추적 | 기억 집합 (힙의 10~20% 사용) | 연결 행렬 (책 기준) | 없음, 매 주기 전체 표시 |
| 동시 이동 해법 | 해당 없음 | 포워딩 포인터 | 컬러 포인터 + 읽기 장벽 + 자가 치유 |
| 대가 | 힙이 커지면 정지 증가 | 장벽 비용으로 처리량 하락 | 처리량 하락, 할당 속도 한계 |

세 컬렉터 모두 "최초 표시" 단계에서 GC 루트를 스캔하며, 셰넌도어와 ZGC의 정지 시간은 사실상 루트 수에 비례한다. 그래서 자연스럽게 다음 질문이 나왔다.

> 실제 Spring 게시판 서버에서는 어떤 객체가 GC 루트이고, 어떤 객체가 루트에 매달려 오래 살며, 그것이 컬렉터별 동작에 어떤 차이를 만드는가?

이 레포는 그 질문을 이론이 아니라 GC 로그, 힙 덤프, JFR로 눈으로 확인하기 위한 것이다.

## 2. 확인하려는 가설

1. 스프링 빈은 GC 루트가 아니다. 루트(스레드, 시스템 클래스)에서 도달 가능해서 죽지 않을 뿐이다.
2. 요청 처리 중의 DTO와 엔티티는 톰캣 워커 스레드 스택의 지역 변수(Java Local 루트)에만 매달려 있고, 요청이 끝나면 에덴에서 바로 죽는다.
3. 누수가 생기면 같은 `Post` 객체의 "루트까지의 경로"가 Java Local에서 System Class 또는 Thread로 바뀐다.
4. 같은 부하에서 G1은 객체 이동 단계(선별 회수)에서 가장 길게 멈추고, 셰넌도어와 ZGC는 이동을 동시에 하므로 정지가 1ms 안팎에 머문다. 대신 처리량(RPS)은 G1이 가장 높다.
5. 구세대에 오래 사는 객체가 늘어날수록(누수 시나리오) G1의 Mixed GC 정지는 길어지지만 셰넌도어와 ZGC의 정지 시간은 거의 변하지 않는다.

## 3. 게시판 서버의 GC 루트 지도 (사전 정리)

진짜 루트
- 스레드 스택 지역 변수: `http-nio-8080-exec-N` 워커가 컨트롤러 → 서비스 → 리포지토리를 타는 동안 프레임에 든 요청 DTO, `Post` 엔티티, 조회 결과 리스트
- 살아있는 스레드 객체: 톰캣 워커 풀, HikariCP housekeeper, `@Scheduled` 스레드
- 시스템 클래스로더가 로드한 클래스와 static 필드
- JNI 참조, `synchronized`로 잡힌 모니터 객체

루트에 매달려 오래 사는 것 (구세대 단골)
- `ApplicationContext` → `DefaultListableBeanFactory.singletonObjects` → 모든 싱글턴 빈
- Hibernate `SessionFactory`, 메타모델, 쿼리 플랜 캐시
- HikariCP 커넥션 풀, Jackson `ObjectMapper` 직렬화기 캐시
- 풀 스레드에 매달린 `ThreadLocal` 값 (`RequestContextHolder`, 트랜잭션 동기화 정보 등)

금방 죽는 것 (에덴에서 끝남)
- 요청/응답 DTO, 페이징 결과, JSON 직렬화 버퍼, 영속성 컨텍스트의 엔티티 스냅숏

## 4. 작업 환경과 제약

- GitHub 계정: `hyujikoh`, 레포 이름: `gc-roots-board-lab`
- 기본 스택: Java 21, Spring Boot 3.x, Gradle (Kotlin DSL), Spring Web + Spring Data JPA, H2 인메모리 DB
- JDK 배포판: Eclipse Temurin 21 또는 Amazon Corretto 21. Oracle JDK 빌드에는 셰넌도어가 없다.
- 부하 도구: k6
- 분석 도구: Eclipse MAT(힙 덤프), JDK Mission Control(JFR), `jcmd`
- 이 레포는 회사 업무와 무관한 개인 학습용이다. 회사 코드, 설정, 자격 증명을 가져오지 않는다.

에이전트가 지켜야 할 것
- 레포 생성, 원격 push, 공개 범위 설정은 실행 전에 작성자에게 확인받는다.
- 토큰, 비밀번호를 파일이나 명령어에 직접 쓰지 않는다. 인증은 작성자가 `gh auth login`으로 직접 한다.
- 실험 결과 수치를 지어내지 않는다. 실행하지 못한 실험은 "미실행"으로 남긴다.

## 5. 레포 구조

```
gc-roots-board-lab/
├── README.md
├── app/                      Spring Boot 게시판
│   └── src/main/java/io/github/hyujikoh/gcroots/
│       ├── post/             Post 엔티티, 리포지토리, 서비스, 컨트롤러, 시더, PostAccessListener 훅
│       └── leak/             누수 시나리오 3종 (프로필로 on/off) + /leak/stats
├── load/board.js             k6 부하 스크립트
├── scripts/
│   ├── run.sh                컬렉터를 인자로 받아 서버 실행
│   ├── run-docker.sh         같은 것을 --cpus/--memory 제한한 컨테이너에서 (Dockerfile 사용)
│   ├── dump.sh               힙 덤프 + 클래스 히스토그램 + 스레드 덤프
│   └── summarize-gc.sh       gc.log 정지 시간 요약
├── results/                  컬렉터·시나리오별 로그와 요약 (대용량은 gitignore)
└── docs/
    ├── 01-gc-roots.md        힙 덤프로 확인한 루트 지도
    ├── 02-collector-compare.md  컬렉터 비교 결과 + 가설 판정
    └── 03-leak-scenarios.md  누수 시나리오별 루트 경로 변화
```

## 6. 실행 옵션

`scripts/run.sh <g1|shenandoah|zgc|zgc-gen> [profile]`

공통: `-Xms1g -Xmx1g -XX:+AlwaysPreTouch -Xlog:gc*,safepoint:file=...:time,uptime,level,tags -XX:StartFlightRecording:settings=profile,path-to-gc-roots=true,...`

| 인자 | 옵션 |
|---|---|
| `g1` | `-XX:+UseG1GC -XX:MaxGCPauseMillis=200` (`MAX_PAUSE` 환경변수로 변경) |
| `shenandoah` | `-XX:+UseShenandoahGC` |
| `zgc` | `-XX:+UseZGC` (JDK 21에서는 비세대 ZGC) |
| `zgc-gen` | `-XX:+UseZGC -XX:+ZGenerational` |

환경변수: `HEAP` (기본 1g), `MAX_PAUSE` (기본 200), `BOARD_SEED_COUNT` (기본 10000), `JAVA_HOME`.

## 7. 누수 시나리오

| 프로필 | 내용 | 예상 루트 경로 |
|---|---|---|
| `leak-static` | 상세 조회 시 `static Map<Long, Post>`에 제한 없이 저장 | System Class → static 필드 → Map → Post |
| `leak-threadlocal` | 필터에서 `ThreadLocal`에 요청 컨텍스트(게시글 리스트 포함)를 넣고 `remove()` 생략 | Thread → threadLocals → Entry → value |
| `leak-listener` | 요청마다 싱글턴 빈의 리스트에 리스너 객체 등록, 해제 없음 | Thread/System Class → ApplicationContext → 싱글턴 빈 → List |

## 8. 컬렉터별 확인 방법

공통: 부하 중 `scripts/dump.sh` → MAT 에서 GC Roots 뷰, `Post` 의 Path to GC Roots (exclude weak/soft). JFR `jdk.OldObjectSample` 로 교차 확인. 자세한 절차는 `docs/01-gc-roots.md`.

G1 로그: `Pause Young (Normal)` / `(Concurrent Start)` / `Concurrent Mark Cycle` / `Pause Remark` / `Pause Cleanup` / `Pause Young (Mixed)`. 누수 프로필에서 Mixed 정지가 늘어나는가. `MAX_PAUSE=50` 이면 CSet 크기와 빈도가 어떻게 바뀌는가.

셰넌도어 로그: `Pause Init Mark` / `Concurrent marking` / `Pause Final Mark` / `Concurrent evacuation` / `Pause Init Update Refs` / `Concurrent update references` / `Pause Final Update Refs` / `Concurrent cleanup`. Pause 가 전부 1ms 안팎인가. `Pacing`, `Degenerated GC`, `Full GC` 발생 여부.

ZGC 로그: `Pause Mark Start` / `Concurrent Mark` / `Pause Mark End` / `Concurrent Select Relocation Set` / `Pause Relocate Start` / `Concurrent Relocate`. Pause 세 개가 모두 1ms 미만인가. `Allocation Stall` 발생 여부. `zgc` vs `zgc-gen` 의 주기 횟수와 CPU.

비교 매트릭스: 컬렉터 4종 × 프로필 4종 = 16회. 시간이 부족하면 default + leak-static 만 먼저.

## 9. 완료 기준

- [x] `./scripts/run.sh g1` 한 줄로 서버가 뜨고, `k6 run load/board.js`로 부하가 걸린다
- [x] 네 가지 컬렉터 설정 모두에서 gc.log와 JFR 파일이 생성된다 (Docker, default 프로필)
- [ ] `docs/01-gc-roots.md`에 정상 프로필의 루트 지도가 기록돼 있다
- [ ] `docs/03-leak-scenarios.md`에 시나리오별 "Path to GC Roots"가 예상 경로와 비교돼 있다
- [ ] `docs/02-collector-compare.md`에 비교 표와 가설 5개 각각의 판정이 적혀 있다

## 10. 참고와 주의

- 이론 부분은 『JVM 밑바닥까지 파헤치기』(JDK 11~17 시점 서술) 기준이다. 이후 변경점
  - 셰넌도어: 포워딩 포인터를 별도 필드 대신 객체 헤더 마크 워드에 저장하도록 변경, 연결 행렬 제거
  - ZGC: JDK 21에서 세대 구분 ZGC 도입, JDK 23부터 기본값. 세대 구분 ZGC는 쓰기 장벽과 기억 집합 성격의 구조를 추가로 사용
- 셰넌도어의 세대 구분 모드는 JDK 21에 없으므로 이 실험 범위에서 제외한다.
- 힙 1GB는 저지연 컬렉터의 장점이 드러나기엔 작은 편이다. 여유가 되면 `HEAP=4g BOARD_SEED_COUNT=100000` 으로 한 번 더 돌려 G1의 정지 시간 증가를 확인한다.
