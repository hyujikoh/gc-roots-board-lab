package io.github.hyujikoh.gcroots.leak;

import io.github.hyujikoh.gcroots.post.Post;
import io.github.hyujikoh.gcroots.post.PostAccessListener;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * [의도적 누수] leak-listener
 * <p>
 * 상세 조회마다 "이 게시글이 갱신되면 알려달라" 는 리스너 객체를 싱글턴 빈의 리스트에 등록하고,
 * 요청이 끝나도 해제(unregister)하지 않는다. 리스너는 Post 를 캡처하고 있으므로 Post 도 함께 살아남는다.
 * <p>
 * 이 시나리오의 핵심은 "스프링 빈은 GC 루트가 아니다"(가설 1) 를 눈으로 보는 것이다.
 * MAT 에서 경로를 따라가면 이 빈(ListenerRegistryLeak) 자체는 루트가 아니고,
 * DefaultListableBeanFactory.singletonObjects 맵을 거쳐 ApplicationContext 까지 올라간 뒤,
 * 그것을 참조하는 스레드(main 의 지역 변수, 또는 톰캣 스레드의 ThreadLocal/컨텍스트) 나
 * System Class 에서 끝난다.
 * <p>
 * 예상 Path to GC Roots (둘 중 하나 또는 둘 다):
 *   Thread/System Class → ... → AnnotationConfigServletWebServerApplicationContext
 *     → beanFactory(DefaultListableBeanFactory) → singletonObjects(ConcurrentHashMap)
 *     → ListenerRegistryLeak → listeners(CopyOnWriteArrayList) → PostUpdateListener → post(Post)
 */
@Component
@Profile("leak-listener")
public class ListenerRegistryLeak implements PostAccessListener {

    // 의도적 누수: 등록만 있고 해제가 없다.
    private final List<PostUpdateListener> listeners = new CopyOnWriteArrayList<>();

    @Override
    public void onPostViewed(Post post) {
        listeners.add(new PostUpdateListener(post));
    }

    public int size() {
        return listeners.size();
    }

    /** 요청 스코프에서 만들어져 싱글턴에 등록된 뒤 잊혀지는 리스너. */
    static final class PostUpdateListener {
        private final Post post;

        PostUpdateListener(Post post) {
            this.post = post;
        }

        void onUpdated() {
            // 실제로는 아무도 부르지 않는다. 참조를 유지하기 위한 존재.
            post.getTitle();
        }
    }
}
