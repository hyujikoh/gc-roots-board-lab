package io.github.hyujikoh.gcroots.leak;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 부하 중 누수가 실제로 자라고 있는지 확인하는 보조 엔드포인트.
 * GET /leak/stats
 */
@RestController
public class LeakStatsController {

    private final Environment env;
    private final ObjectProvider<ListenerRegistryLeak> listenerLeak;

    public LeakStatsController(Environment env, ObjectProvider<ListenerRegistryLeak> listenerLeak) {
        this.env = env;
        this.listenerLeak = listenerLeak;
    }

    @GetMapping("/leak/stats")
    public Map<String, Object> stats() {
        var out = new LinkedHashMap<String, Object>();
        out.put("activeProfiles", List.of(env.getActiveProfiles()));
        out.put("staticMapEntries", StaticMapLeak.size());
        out.put("listenerRegistrySize", listenerLeak.getIfAvailable() == null ? 0 : listenerLeak.getObject().size());
        // ThreadLocal 누수는 스레드별이라 총합을 안전하게 셀 수 없다. 현재 스레드 값만 참고용으로 노출.
        // (정상 프로필에서는 HISTORY.get() 자체가 빈 리스트를 스레드에 남기므로 프로필이 켜졌을 때만 읽는다)
        boolean threadLocalLeakOn = env.matchesProfiles("leak-threadlocal");
        out.put("threadLocalHistoryOnThisThread", threadLocalLeakOn ? ThreadLocalLeakFilter.HISTORY.get().size() : 0);
        return out;
    }
}
