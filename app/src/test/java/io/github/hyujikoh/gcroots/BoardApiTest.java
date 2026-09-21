package io.github.hyujikoh.gcroots;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = "board.seed.count=50")
@AutoConfigureMockMvc
class BoardApiTest {

    @Autowired
    MockMvc mvc;

    @Test
    void seedsAndServesPosts() throws Exception {
        mvc.perform(get("/posts/count"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(50));

        mvc.perform(get("/posts").param("page", "0").param("size", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(10))
                .andExpect(jsonPath("$.totalElements").value(50));

        mvc.perform(get("/posts/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.viewCount").value(1))
                .andExpect(jsonPath("$.content.length()").value(greaterThanOrEqualTo(1024)));
    }

    @Test
    void createsPost() throws Exception {
        mvc.perform(post("/posts").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"t\",\"content\":\"c\",\"author\":\"a\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").exists());
    }
}
