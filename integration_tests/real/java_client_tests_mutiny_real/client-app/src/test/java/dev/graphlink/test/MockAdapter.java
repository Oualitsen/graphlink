package dev.graphlink.test;

import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter;
import io.smallrye.mutiny.Uni;

public class MockAdapter extends MockAdapterCore implements GraphLinkClientAdapter {
    @Override
    public Uni<String> execute(String payload) {
        return Rx.deferred(() -> handle(payload));
    }
}
