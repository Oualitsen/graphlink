package dev.graphlink.server.apq;

import graphql.ExecutionResult;
import graphql.ExecutionResultImpl;
import graphql.GraphqlErrorBuilder;
import org.springframework.graphql.support.DefaultExecutionGraphQlResponse;
import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.graphql.server.WebGraphQlRequest;
import org.springframework.graphql.server.WebGraphQlResponse;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;

@Component
public class PersistedQueryInterceptor implements WebGraphQlInterceptor {

    private static final String MARKER = "PersistedQueryMarker";

    private final PersistedQueryStore store;

    public PersistedQueryInterceptor(PersistedQueryStore store) {
        this.store = store;
    }

    @Override
    public Mono<WebGraphQlResponse> intercept(WebGraphQlRequest request, Chain chain) {
        if (!(request.getExtensions().get("persistedQuery") instanceof Map<?, ?> persisted)) {
            return chain.next(request);
        }
        if (!store.isSupported()) {
            return error(request, "PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED");
        }
        String hash = String.valueOf(persisted.get("sha256Hash"));
        String document = request.getDocument();
        boolean hashOnly = document == null || document.isBlank() || MARKER.equals(document);

        if (hashOnly) {
            Optional<String> query = store.find(hash);
            if (query.isEmpty()) {
                return error(request, "PersistedQueryNotFound", "PERSISTED_QUERY_NOT_FOUND");
            }
            request.configureExecutionInput((input, builder) -> builder.query(query.get()).build());
            return chain.next(request);
        }
        if (!sha256(document).equals(hash)) {
            return error(request, "provided sha does not match query", "INTERNAL_SERVER_ERROR");
        }
        store.register(hash, document);
        return chain.next(request);
    }

    private Mono<WebGraphQlResponse> error(WebGraphQlRequest request, String message, String code) {
        ExecutionResult result = ExecutionResultImpl.newExecutionResult()
                .addError(GraphqlErrorBuilder.newError()
                        .message(message)
                        .extensions(Map.of("code", code))
                        .build())
                .build();
        return Mono.just(new WebGraphQlResponse(
                new DefaultExecutionGraphQlResponse(request.toExecutionInput(), result)));
    }

    private static String sha256(String text) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
