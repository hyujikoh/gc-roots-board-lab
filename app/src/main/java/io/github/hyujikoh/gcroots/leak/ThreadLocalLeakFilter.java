package io.github.hyujikoh.gcroots.leak;

import io.github.hyujikoh.gcroots.post.Post;
import io.github.hyujikoh.gcroots.post.PostAccessListener;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * [의도적 누수] leak-threadlocal
 * <p>
 * 필터에서 요청마다 RequestContext 를 만들어 ThreadLocal 에 넣고, 요청이 끝나도 remove() 를 부르지 않는다.
 * ThreadLocal 값 하나는 스레드당 최신 값 하나뿐이라 그대로는 누수가 스레드 수로 제한된다.
 * 그래서 값의 타입을 "이 스레드가 처리한 요청 컨텍스트 목록" 으로 잡아 계속 append 한다.
 * (실무에서 "디버깅용 요청 히스토리" 를 ThreadLocal 에 쌓다가 생기는 전형적 패턴)
 * <p>
 * 톰캣 워커 스레드는 풀에 살아있으므로 스레드 객체가 GC 루트(Thread)가 되고, 그 threadLocals 맵을 통해
 * 모든 컨텍스트와 그 안의 Post 리스트가 살아남는다.
 * <p>
 * 예상 Path to GC Roots:
 *   Thread (http-nio-8080-exec-N) → threadLocals → ThreadLocalMap.Entry → value(ArrayList)
 *     → RequestContext → posts(List) → Post
 */
@Component
@Profile("leak-threadlocal")
public class ThreadLocalLeakFilter extends OncePerRequestFilter implements PostAccessListener {

    // 의도적 누수: remove() 를 부르는 곳이 없다.
    static final ThreadLocal<List<RequestContext>> HISTORY = ThreadLocal.withInitial(ArrayList::new);
    private static final AtomicLong LIST_SAMPLE = new AtomicLong();
    private static final int LIST_SAMPLE_RATE = 25;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        var ctx = new RequestContext(request.getMethod() + " " + request.getRequestURI(), Instant.now());
        HISTORY.get().add(ctx);
        try {
            chain.doFilter(request, response);
        } finally {
            // 여기서 HISTORY.remove() 를 호출해야 정상이다. 의도적으로 생략.
        }
    }

    @Override
    public void onPostsListed(List<Post> posts) {
        // 목록 요청은 전체 트래픽의 70%, 한 번에 20건이라 전부 붙잡으면 1GB 힙이 1분 안에 OOM 난다.
        // 3분 부하 동안 수백 MB 정도만 자라도록 25번에 1번만 리스트 전체를 붙잡는다.
        if (LIST_SAMPLE.incrementAndGet() % LIST_SAMPLE_RATE == 0) {
            current().posts.addAll(posts);
        }
    }

    @Override
    public void onPostViewed(Post post) {
        current().posts.add(post);
    }

    private static RequestContext current() {
        List<RequestContext> history = HISTORY.get();
        return history.get(history.size() - 1);
    }

    static final class RequestContext {
        final String requestLine;
        final Instant startedAt;
        final List<Post> posts = new ArrayList<>();

        RequestContext(String requestLine, Instant startedAt) {
            this.requestLine = requestLine;
            this.startedAt = startedAt;
        }
    }
}
