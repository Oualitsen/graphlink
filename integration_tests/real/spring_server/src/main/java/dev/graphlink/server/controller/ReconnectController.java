package dev.graphlink.server.controller;

import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Controller
public class ReconnectController {

    private static final Map<String, AtomicInteger> STARTS = new ConcurrentHashMap<>();

    @SubscriptionMapping
    public Flux<String> labelTicks(@Argument String label, @Argument int count) {
        STARTS.computeIfAbsent(label, k -> new AtomicInteger()).incrementAndGet();
        return Flux.interval(Duration.ofMillis(100)).take(count).map(i -> label + "-" + (i + 1));
    }

    @QueryMapping
    public int labelTickStarts(@Argument String label) {
        AtomicInteger starts = STARTS.get(label);
        return starts == null ? 0 : starts.get();
    }
}
