package dev.graphlink.restmock;

import dev.graphlink.restmock.generated.client.GLRestAdapter;
import dev.graphlink.restmock.generated.client.RestRequest;
import dev.graphlink.restmock.generated.client.RestResponse;
import io.smallrye.mutiny.Uni;

final class MockRest extends MockRestCore implements GLRestAdapter {
    @Override
    public Uni<RestResponse> execute(RestRequest request) {
        return Rx.deferred(() -> handle(request));
    }
}
