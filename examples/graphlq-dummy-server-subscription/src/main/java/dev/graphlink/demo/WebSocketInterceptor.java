package dev.graphlink.demo;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.graphql.server.*;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketInterceptor implements WebSocketGraphQlInterceptor {




    @Override
    public Mono<Object> handleConnectionInitialization(WebSocketSessionInfo sessionInfo,
                                                        Map<String, Object> connectionInitPayload) {
        log.info("[WS] CONNECTED from {} payload={}", sessionInfo.getRemoteAddress(), connectionInitPayload);
        return Mono.just(Map.of());
    }

    @Override
    public void handleConnectionClosed(WebSocketSessionInfo sessionInfo, int statusCode, Map<String, Object> connectionInitPayload) {
        log.info("[WS] DISCONNECTED status={}", statusCode);
    }

    @Override
    public Mono<WebGraphQlResponse> intercept(WebGraphQlRequest request, Chain chain) {
        log.info("[WS][IN]  {}", request.getDocument());
        return chain.next(request)
                .doOnNext(response -> log.info("[WS][OUT] {}", (Object) response.getData()));
    }
}
