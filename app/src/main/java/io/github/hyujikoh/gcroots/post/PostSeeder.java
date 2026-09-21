package io.github.hyujikoh.gcroots.post;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 기동 시 더미 게시글을 적재한다. 기본 1만 건, 본문 1~4KB.
 * <p>
 * 적재가 끝나면 이 Runner 가 만든 Post 객체들은 모두 지역 변수 밖으로 벗어나 죽고,
 * DB(H2 인메모리)에만 남는다. 즉 힙에 남는 것은 H2 내부 자료구조이지 Post 인스턴스가 아니다.
 * 이 점은 힙 덤프에서 "Post 인스턴스가 왜 이렇게 적지?" 라고 놀라지 않기 위해 미리 적어둔다.
 */
@Component
public class PostSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(PostSeeder.class);
    private static final String ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";
    private static final int BATCH = 500;

    private final PostRepository postRepository;
    private final SeedProperties props;

    public PostSeeder(PostRepository postRepository, SeedProperties props) {
        this.postRepository = postRepository;
        this.props = props;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (postRepository.count() > 0) {
            return;
        }
        long start = System.currentTimeMillis();
        List<Post> batch = new ArrayList<>(BATCH);
        for (int i = 1; i <= props.count(); i++) {
            batch.add(new Post("post-" + i, randomBody(), "author-" + (i % 100)));
            if (batch.size() == BATCH) {
                postRepository.saveAll(batch);
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            postRepository.saveAll(batch);
        }
        log.info("seeded {} posts in {} ms", props.count(), System.currentTimeMillis() - start);
    }

    private String randomBody() {
        var rnd = ThreadLocalRandom.current();
        int len = rnd.nextInt(props.minBodyBytes(), props.maxBodyBytes() + 1);
        var sb = new StringBuilder(len);
        for (int i = 0; i < len; i++) {
            sb.append(ALPHABET.charAt(rnd.nextInt(ALPHABET.length())));
        }
        return sb.toString();
    }

    @ConfigurationProperties(prefix = "board.seed")
    public record SeedProperties(int count, int minBodyBytes, int maxBodyBytes) {
    }
}
