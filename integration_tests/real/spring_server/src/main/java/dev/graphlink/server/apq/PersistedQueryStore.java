package dev.graphlink.server.apq;

import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Component
public class PersistedQueryStore {

    private final Map<String, String> queries = new ConcurrentHashMap<>();
    private final AtomicInteger hits = new AtomicInteger();
    private final AtomicInteger misses = new AtomicInteger();
    private final AtomicInteger registrations = new AtomicInteger();
    private volatile boolean supported = true;

    public Optional<String> find(String hash) {
        Optional<String> query = Optional.ofNullable(queries.get(hash));
        (query.isPresent() ? hits : misses).incrementAndGet();
        return query;
    }

    public void register(String hash, String query) {
        if (queries.put(hash, query) == null) registrations.incrementAndGet();
    }

    public boolean isSupported() {
        return supported;
    }

    public void setSupported(boolean supported) {
        this.supported = supported;
    }

    public void evict() {
        queries.clear();
    }

    public void reset() {
        queries.clear();
        hits.set(0);
        misses.set(0);
        registrations.set(0);
        supported = true;
    }

    public Map<String, Object> stats() {
        return Map.of(
                "supported", supported,
                "stored", queries.size(),
                "hits", hits.get(),
                "misses", misses.get(),
                "registrations", registrations.get());
    }
}
