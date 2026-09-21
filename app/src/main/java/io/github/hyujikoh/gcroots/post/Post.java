package io.github.hyujikoh.gcroots.post;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * 게시글 엔티티.
 * <p>
 * 힙 덤프에서 이 클래스 인스턴스의 "Path to GC Roots"를 추적하는 것이 실험의 핵심이다.
 * 정상 프로필에서는 요청을 처리 중인 톰캣 워커 스레드의 Java Local 에만 매달려야 하고,
 * 누수 프로필에서는 System Class(static) 또는 Thread(threadLocals) 로 경로가 바뀌어야 한다.
 */
@Entity
@Table(name = "posts")
public class Post {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 200)
    private String title;

    /** 1~4KB 랜덤 문자열. 할당 압력을 만들기 위해 일부러 크게 잡는다. */
    @Lob
    @Column(nullable = false)
    private String content;

    @Column(nullable = false, length = 50)
    private String author;

    @Column(nullable = false)
    private long viewCount;

    @Column(nullable = false)
    private LocalDateTime createdAt;

    protected Post() {
    }

    public Post(String title, String content, String author) {
        this.title = title;
        this.content = content;
        this.author = author;
        this.viewCount = 0L;
        this.createdAt = LocalDateTime.now();
    }

    public void increaseViewCount() {
        this.viewCount++;
    }

    public Long getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public String getContent() {
        return content;
    }

    public String getAuthor() {
        return author;
    }

    public long getViewCount() {
        return viewCount;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }
}
