package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;

import java.util.Map;

final class Helpers {
    private Helpers() {}

    static GraphLinkClient newClient(ApqServer server) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        return new GraphLinkClient(server.post, server.get, null, codec, codec, new MockWebSocketAdapter());
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> hashOf(Map<String, Object> request) {
        return (Map<String, Object>) ((Map<String, Object>) request.get("extensions")).get("persistedQuery");
    }

    static CreateUserInput createUserInput() {
        return CreateUserInput.builder()
                .name("Alice")
                .email("a@test.com")
                .status(UserStatus.ACTIVE)
                .address(AddressInput.builder().street("s").city("c").country("x").build())
                .build();
    }
}
