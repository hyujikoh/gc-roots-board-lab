package io.github.hyujikoh.gcroots.post;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 요청/응답 DTO 모음.
 * 모두 요청 처리 중 워커 스레드 스택에만 매달렸다가 응답 직렬화 후 에덴에서 죽어야 하는 객체들이다.
 */
public final class PostDtos {

    private PostDtos() {
    }

    public record CreateRequest(
            @NotBlank @Size(max = 200) String title,
            @NotBlank String content,
            @NotBlank @Size(max = 50) String author
    ) {
    }

    /** 목록용 요약. 본문은 제외해 목록 응답 크기를 줄인다. */
    public record Summary(Long id, String title, String author, long viewCount, LocalDateTime createdAt) {
        static Summary from(Post post) {
            return new Summary(post.getId(), post.getTitle(), post.getAuthor(), post.getViewCount(), post.getCreatedAt());
        }
    }

    /** 상세 응답. 본문(1~4KB) 포함. */
    public record Detail(Long id, String title, String content, String author, long viewCount, LocalDateTime createdAt) {
        static Detail from(Post post) {
            return new Detail(post.getId(), post.getTitle(), post.getContent(), post.getAuthor(),
                    post.getViewCount(), post.getCreatedAt());
        }
    }

    public record Page(List<Summary> items, int page, int size, long totalElements, int totalPages) {
    }
}
