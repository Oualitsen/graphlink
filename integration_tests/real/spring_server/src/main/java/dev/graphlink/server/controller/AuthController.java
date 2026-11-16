package dev.graphlink.server.controller;

import dev.graphlink.server.AuthInterceptor;
import graphql.GraphqlErrorException;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.ContextValue;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Controller
public class AuthController {

    private static final String BEARER = "Bearer ";
    private static final Map<String, AtomicInteger> SECURE_STARTS = new ConcurrentHashMap<>();

    @QueryMapping
    public String echoHeader(@Argument String name, @ContextValue(name = AuthInterceptor.HEADERS) HttpHeaders headers) {
        return headers.getFirst(name);
    }

    @QueryMapping
    public String whoAmI(@ContextValue(name = AuthInterceptor.HEADERS) HttpHeaders headers) {
        return bearerToken(headers.getFirst(HttpHeaders.AUTHORIZATION));
    }

    @QueryMapping
    public int secureTickStarts(@Argument String token) {
        AtomicInteger starts = SECURE_STARTS.get(token);
        return starts == null ? 0 : starts.get();
    }

    @SubscriptionMapping
    public Flux<Integer> secureTicks(
            @Argument int count,
            @ContextValue(name = AuthInterceptor.CONNECTION_TOKEN, required = false) String connectionToken) {
        String token;
        try {
            token = bearerToken(connectionToken);
        } catch (GraphqlErrorException e) {
            return Flux.error(e);
        }
        SECURE_STARTS.computeIfAbsent(token, k -> new AtomicInteger()).incrementAndGet();
        return Flux.interval(Duration.ofMillis(100)).take(count).map(i -> i.intValue() + 1);
    }

    private static String bearerToken(String authorization) {
        if (authorization == null || !authorization.startsWith(BEARER) || authorization.length() == BEARER.length()) {
            throw GraphqlErrorException.newErrorException().message("unauthenticated").build();
        }
        return authorization.substring(BEARER.length());
    }
}
