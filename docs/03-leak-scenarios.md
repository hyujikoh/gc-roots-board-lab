# 03. 누수 시나리오별 GC 루트 경로 변화

> 상태: **미실행**. 각 시나리오마다 부하 중 힙 덤프를 뜨고, MAT 의 "Merge Shortest Paths to GC Roots (exclude weak/soft)" 결과를 그대로 붙여넣는다.

## 공통 절차

```
scripts/run.sh g1 <profile>          # 터미널 1
k6 run -e DURATION=2m load/board.js  # 터미널 2
scripts/dump.sh g1 <profile> mid     # 터미널 3, 부하 시작 60초 뒤
curl -s localhost:8080/leak/stats    # 누수가 실제로 자라는지 확인
```

MAT 에서 확인할 것
1. Histogram 에서 `Post` 인스턴스 수 (정상 프로필과 비교. 수십 → 수만으로 늘어야 한다)
2. `Post` → Merge Shortest Paths to GC Roots → exclude all phantom/weak/soft
3. Dominator Tree 상위에 누수 컨테이너(Map / ArrayList / ThreadLocalMap)가 올라오는지
4. Leak Suspects 리포트가 같은 지점을 가리키는지

## 시나리오 1. leak-static (`StaticMapLeak`)

코드: 상세 조회마다 `static Map<Long, Post> CACHE` 에 조회 순번을 키로 Post 를 넣고 절대 제거하지 않음.

예상 경로

```
Post
 └─ value of java.util.concurrent.ConcurrentHashMap$Node
     └─ java.util.concurrent.ConcurrentHashMap$Node[] (table)
         └─ java.util.concurrent.ConcurrentHashMap
             └─ <System Class> io.github.hyujikoh.gcroots.leak.StaticMapLeak  ← static CACHE
```

실제 경로

```
(붙여넣기)
```

| 항목 | 정상 | leak-static |
|---|---|---|
| Post 인스턴스 수 | | |
| Post 총 retained 크기 | | |
| `/leak/stats` staticMapEntries (덤프 시점) | 0 | |

판정: (예상과 일치 / 불일치 / 미확인)

## 시나리오 2. leak-threadlocal (`ThreadLocalLeakFilter`)

코드: 필터가 요청마다 `RequestContext` 를 만들어 `ThreadLocal<List<RequestContext>>` 에 append 하고 `remove()` 생략. 상세 조회 Post 와 (25회에 1회) 목록 Post 리스트를 컨텍스트에 붙잡음.

예상 경로

```
Post
 └─ java.lang.Object[] (ArrayList.elementData)
     └─ java.util.ArrayList (RequestContext.posts)
         └─ ThreadLocalLeakFilter$RequestContext
             └─ java.lang.Object[] → java.util.ArrayList (HISTORY 값)
                 └─ java.lang.ThreadLocal$ThreadLocalMap$Entry (value)
                     └─ java.lang.ThreadLocal$ThreadLocalMap$Entry[] (table)
                         └─ java.lang.ThreadLocal$ThreadLocalMap (Thread.threadLocals)
                             └─ <Thread> http-nio-8080-exec-N
```

실제 경로

```
(붙여넣기)
```

관찰 포인트
- 워커 스레드마다 하나씩, 톰캣 스레드 수(최대 100)만큼 경로가 갈라지는가
- MAT Thread Overview 에서 `http-nio-8080-exec-N` 의 retained heap 이 정상 대비 얼마나 커졌는가

판정: (예상과 일치 / 불일치 / 미확인)

## 시나리오 3. leak-listener (`ListenerRegistryLeak`)

코드: 상세 조회마다 `PostUpdateListener(post)` 를 싱글턴 빈의 `CopyOnWriteArrayList` 에 등록, 해제 없음.

예상 경로

```
Post
 └─ ListenerRegistryLeak$PostUpdateListener.post
     └─ java.lang.Object[] (CopyOnWriteArrayList.array)
         └─ java.util.concurrent.CopyOnWriteArrayList (listeners)
             └─ io.github.hyujikoh.gcroots.leak.ListenerRegistryLeak      ← 빈. 여기가 루트가 아님에 주목
                 └─ ConcurrentHashMap$Node → ConcurrentHashMap (singletonObjects)
                     └─ org.springframework.beans.factory.support.DefaultListableBeanFactory
                         └─ AnnotationConfigServletWebServerApplicationContext
                             └─ (Thread main 의 Java Local, 또는 TomcatWebServer/Servlet 컨텍스트 경유 → Thread / System Class)
```

실제 경로

```
(붙여넣기)
```

관찰 포인트
- ApplicationContext 위로 올라가서 진짜 루트가 무엇으로 끝나는가 (가설 1 의 직접 증거)
- CopyOnWriteArrayList 는 add 마다 배열을 복사하므로 이 시나리오는 할당 압력도 같이 커진다. G1 로그의 Young GC 빈도가 다른 시나리오보다 높은지

판정: (예상과 일치 / 불일치 / 미확인)

## 시나리오 간 비교

| | 정상 | leak-static | leak-threadlocal | leak-listener |
|---|---|---|---|---|
| Post 인스턴스 수 (덤프 시점) | | | | |
| Post 경로의 루트 종류 | Java Local | System Class | Thread | Thread / System Class (ApplicationContext 경유) |
| 구세대 점유 (gc.log 마지막 old 크기) | | | | |
| G1 Mixed GC 최대 정지(ms) | | | | |
| 셰넌도어 최대 Pause(ms) | | | | |
| ZGC 최대 Pause(ms) | | | | |

가설 3 판정: (맞음 / 틀림 / 미확인)
가설 5 판정: (맞음 / 틀림 / 미확인)
