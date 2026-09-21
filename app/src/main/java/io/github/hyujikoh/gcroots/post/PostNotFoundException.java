package io.github.hyujikoh.gcroots.post;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

public class PostNotFoundException extends ResponseStatusException {

    public PostNotFoundException(Long id) {
        super(HttpStatus.NOT_FOUND, "post not found: " + id);
    }
}
