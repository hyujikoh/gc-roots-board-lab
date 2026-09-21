package io.github.hyujikoh.gcroots.post;

import java.util.List;

/**
 * 게시글 접근 훅.
 * <p>
 * 정상 프로필에서는 구현체가 하나도 없다. 누수 프로필(leak-*)에서만 구현체 빈이 등록되어
 * 조회된 Post 를 어딘가에 "붙잡아" GC 루트까지의 경로를 바꾼다.
 */
public interface PostAccessListener {

    default void onPostViewed(Post post) {
    }

    default void onPostsListed(List<Post> posts) {
    }
}
