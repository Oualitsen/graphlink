package dev.graphlink.server.apq;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/test/apq")
public class PersistedQueryTestController {

    private final PersistedQueryStore store;

    public PersistedQueryTestController(PersistedQueryStore store) {
        this.store = store;
    }

    @GetMapping
    public Map<String, Object> stats() {
        return store.stats();
    }

    @PostMapping("/evict")
    public Map<String, Object> evict() {
        store.evict();
        return store.stats();
    }

    @PostMapping("/reset")
    public Map<String, Object> reset() {
        store.reset();
        return store.stats();
    }

    @PostMapping("/supported/{value}")
    public Map<String, Object> supported(@PathVariable boolean value) {
        store.setSupported(value);
        return store.stats();
    }
}
