# 01. 힙 덤프로 확인한 GC 루트 지도 (정상 프로필)

> 상태: **미실행**. 아래 절차대로 덤프를 뜬 뒤 "결과" 절을 채운다. 수치·경로는 실제 MAT 출력만 적는다.

## 절차

1. 서버 기동: `scripts/run.sh g1` (루트 지도는 컬렉터와 무관하므로 G1 하나로 충분)
2. 부하: `k6 run -e DURATION=2m load/board.js`
3. 부하 시작 30초 뒤: `scripts/dump.sh g1 default mid`
   - `results/g1/default/dump-mid.hprof`, `histogram-mid.txt`, `threads-mid.txt` 생성
4. Eclipse MAT 에서 `dump-mid.hprof` 열기
   - 인덱스 생성 후 Overview 의 "Leak Suspects" 는 참고만
   - **GC Roots 뷰**: Query Browser → `GC Roots` → 루트 종류별 개수 기록
   - **Post 경로**: Histogram → `io.github.hyujikoh.gcroots.post.Post` 우클릭
     → Merge Shortest Paths to GC Roots → exclude all phantom/weak/soft references
   - **싱글턴 빈 경로**: Histogram → `PostService` → Path to GC Roots. "빈은 루트가 아니다"(가설 1) 확인용
   - **ThreadLocal**: Thread Overview → `http-nio-8080-exec-1` → threadLocals 펼쳐 보기
5. JFR 교차 확인: JDK Mission Control 에서 `rec.jfr` → Event Browser → `jdk.OldObjectSample`
   - Path to GC Roots 열이 채워져 있는지 (run.sh 가 `path-to-gc-roots=true` 로 녹화)

## 결과

### GC Roots 종류별 개수

| 루트 종류 (MAT 표기) | 개수 | 대표 예 |
|---|---|---|
| Thread | | |
| Java Local | | |
| System Class | | |
| JNI Global / JNI Local | | |
| Busy Monitor | | |
| Native Stack | | |
| 기타 | | |

### Post 인스턴스 개수와 위치

- 힙 덤프 시점 `Post` 인스턴스 수: (histogram-mid.txt 에서)
- 기대: 워커 스레드 수 × 페이지 크기(20) 내외. 1만 건 더미는 DB(H2)에 있지 Post 객체로 살아있지 않다.

### Post → GC Root 경로 (Merge Shortest Paths 결과 붙여넣기)

```
(예상)
Post
 └─ [0] java.lang.Object[] (ArrayList.elementData)
     └─ java.util.ArrayList
         └─ <Java Local> http-nio-8080-exec-7  ← PostService.list() 프레임의 posts 지역 변수
```

실제:

```
(붙여넣기)
```

### 싱글턴 빈(PostService) → GC Root 경로

```
(붙여넣기)
```

가설 1 판정: (맞음 / 틀림 / 미확인) — 근거:

### 워커 스레드 threadLocals 내용

| ThreadLocal 키 클래스 | 값 클래스 | 비고 |
|---|---|---|
| | | |

## 메모

- 덤프 시각의 safepoint 로그: `grep HeapDumper results/g1/default/gc.log` 또는 `[safepoint]` 라인에서 `Total:` 이 가장 큰 것
