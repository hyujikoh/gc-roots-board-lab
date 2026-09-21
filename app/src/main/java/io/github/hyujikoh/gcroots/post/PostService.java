package io.github.hyujikoh.gcroots.post;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class PostService {

    private final PostRepository postRepository;
    private final List<PostAccessListener> listeners;

    public PostService(PostRepository postRepository, ObjectProvider<PostAccessListener> listeners) {
        this.postRepository = postRepository;
        // 정상 프로필에는 리스너 빈이 하나도 없다. List<...> 직접 주입은 빈이 0개면 실패하므로 ObjectProvider 로 받는다.
        this.listeners = listeners.orderedStream().toList();
    }

    @Transactional
    public PostDtos.Detail create(PostDtos.CreateRequest request) {
        Post saved = postRepository.save(new Post(request.title(), request.content(), request.author()));
        return PostDtos.Detail.from(saved);
    }

    @Transactional(readOnly = true)
    public PostDtos.Page list(int page, int size) {
        var pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "id"));
        var result = postRepository.findAll(pageable);
        // result.getContent() 는 이 프레임(워커 스레드 스택)에만 매달린 지역 변수다.
        // 정상 프로필이라면 응답을 만든 뒤 이 리스트와 안의 Post 들은 에덴에서 그대로 죽는다.
        List<Post> posts = result.getContent();
        listeners.forEach(l -> l.onPostsListed(posts));
        return new PostDtos.Page(
                posts.stream().map(PostDtos.Summary::from).toList(),
                result.getNumber(), result.getSize(), result.getTotalElements(), result.getTotalPages());
    }

    @Transactional
    public PostDtos.Detail view(Long id) {
        Post post = postRepository.findById(id)
                .orElseThrow(() -> new PostNotFoundException(id));
        post.increaseViewCount();
        listeners.forEach(l -> l.onPostViewed(post));
        return PostDtos.Detail.from(post);
    }

    public long count() {
        return postRepository.count();
    }
}
