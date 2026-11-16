package dev.graphlink.server;

import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.graphql.server.WebGraphQlRequest;
import org.springframework.graphql.server.WebGraphQlResponse;
import org.springframework.graphql.server.WebSocketGraphQlInterceptor;
import org.springframework.graphql.server.WebSocketGraphQlRequest;
import org.springframework.graphql.server.WebSocketSessionInfo;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.Map;

/** Puts the request headers and the connection_init payload token where the controllers can read them. */
@Component
public class AuthInterceptor implements WebSocketGraphQlInterceptor {

    public static final String HEADERS = "headers";
    public static final String CONNECTION_TOKEN = "connectionToken";

    @Override
    public Mono<Object> handleConnectionInitialization(WebSocketSessionInfo session, Map<String, Object> payload) {
        Object authorization = payload == null ? null : payload.get("Authorization");
        if (authorization instanceof String token) {
            session.getAttributes().put(CONNECTION_TOKEN, token);
        }
        Object delay = payload == null ? null : payload.get("Ack-Delay");
        if (delay instanceof String millis) {
            return Mono.delay(Duration.ofMillis(Long.parseLong(millis))).then(Mono.empty());
        }
        return Mono.empty();
    }

    @Override
    public Mono<WebGraphQlResponse> intercept(WebGraphQlRequest request, WebGraphQlInterceptor.Chain chain) {
        request.configureExecutionInput((input, builder) -> builder.graphQLContext(context -> {
            context.put(HEADERS, request.getHeaders());
            if (request instanceof WebSocketGraphQlRequest ws) {
                Object token = ws.getSessionInfo().getAttributes().get(CONNECTION_TOKEN);
                if (token != null) context.put(CONNECTION_TOKEN, token);
            }
        }).build());
        return chain.next(request);
    }
}
