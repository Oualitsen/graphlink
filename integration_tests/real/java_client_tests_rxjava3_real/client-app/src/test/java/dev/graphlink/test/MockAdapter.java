package dev.graphlink.test;

import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter;
import io.reactivex.rxjava3.core.Single;

public class MockAdapter extends MockAdapterCore implements GraphLinkClientAdapter {
    @Override
    public Single<String> execute(String payload) {
        return Rx.deferred(() -> handle(payload));
    }
}
