package dev.graphlink.server;

import dev.graphlink.server.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.server.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.client.JacksonGraphLinkJsonCodec;

public final class Fixtures {

    private Fixtures() {}

    private static int port() {
        String env = System.getenv("SERVER_PORT");
        try {
            return env != null ? Integer.parseInt(env) : 9997;
        } catch (NumberFormatException e) {
            return 9997;
        }
    }

    public static final String SERVER_URL = "http://localhost:" + port() + "/graphql";
    public static final String WS_URL = "ws://localhost:" + port() + "/graphql";

    public static GraphLinkClient newClient() {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        return new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(SERVER_URL),
                codec, codec,
                new DefaultGraphLinkWebSocketAdapter(WS_URL));
    }
}
