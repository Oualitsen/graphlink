package dev.graphlink.test;

import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter;
import reactor.core.publisher.Mono;

public class MockAdapter extends MockAdapterCore implements GraphLinkClientAdapter {
    @Override
    public Mono<String> execute(String payload) {
        return Rx.deferred(() -> handle(payload));
    }
}
