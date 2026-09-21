package io.github.hyujikoh.gcroots.post;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/posts")
public class PostController {

    private final PostService postService;

    public PostController(PostService postService) {
        this.postService = postService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PostDtos.Detail create(@Valid @RequestBody PostDtos.CreateRequest request) {
        return postService.create(request);
    }

    @GetMapping
    public PostDtos.Page list(@RequestParam(defaultValue = "0") int page,
                              @RequestParam(defaultValue = "20") int size) {
        return postService.list(page, Math.min(size, 100));
    }

    @GetMapping("/{id}")
    public PostDtos.Detail view(@PathVariable Long id) {
        return postService.view(id);
    }

    /** k6 스크립트가 id 범위를 알기 위해 쓰는 보조 엔드포인트. */
    @GetMapping("/count")
    public Map<String, Long> count() {
        return Map.of("count", postService.count());
    }
}
