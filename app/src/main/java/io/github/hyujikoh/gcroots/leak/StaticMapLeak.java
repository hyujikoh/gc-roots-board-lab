package io.github.hyujikoh.gcroots.leak;

import io.github.hyujikoh.gcroots.post.Post;
import io.github.hyujikoh.gcroots.post.PostAccessListener;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * [의도적 누수] leak-static
 * <p>
 * 상세 조회마다 Post 를 static Map 에 제한 없이 넣고 절대 제거하지 않는다.
 * 키를 게시글 id 가 아니라 조회 순번으로 잡아 같은 글을 다시 조회해도 덮어쓰지 않게 했다.
 * 그래야 부하 시간에 비례해 구세대가 단조 증가하고, G1 Mixed GC 정지 시간 변화(가설 5)를 볼 수 있다.
 * (1GB 힙, 3분 부하 기준으로 대략 수백 MB 까지 자라며 OOM 은 나지 않는 수준이다.)
 * <p>
 * 예상 Path to GC Roots:
 *   System Class (StaticMapLeak) → static CACHE → ConcurrentHashMap → Node[] → Node → value(Post)
 */
@Component
@Profile("leak-static")
public class StaticMapLeak implements PostAccessListener {

    // 의도적 누수: static 필드는 시스템 클래스로더가 로드한 클래스에 매달리므로 GC 루트에서 항상 도달 가능하다.
    static final Map<Long, Post> CACHE = new ConcurrentHashMap<>();
    private static final AtomicLong SEQ = new AtomicLong();

    @Override
    public void onPostViewed(Post post) {
        CACHE.put(SEQ.incrementAndGet(), post);
    }

    public static int size() {
        return CACHE.size();
    }
}
