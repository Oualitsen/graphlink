package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.GlInterceptorTag;
import dev.graphlink.javaserver.generated.interfaces.GraphLinkInterceptor;
import graphql.GraphQLContext;

import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.List;

@Component
public class InterceptorImpl implements GraphLinkInterceptor {

    @Override
    public Mono<Void> runBefore(GlInterceptorTag tag, String operation, List<Object> args, GraphQLContext context) {
        return Mono.fromRunnable(() -> {
            // `Team.members(role: String!)` demonstrates the throw-to-deny
            // contract directly: this is the batch-mapping equivalent of the
            // marker approach used everywhere else, but sidesteps the fact
            // that batch mappings can't reliably pass state back through the
            // request context.
            if (operation.equals("Team.members")) {
                Object role = args.get(0);
                if (!"auth".equals(role)) {
                    throw new RuntimeException("Access denied: role \"" + role + "\" is not permitted");
                }
                return;
            }

            // Mapping/batch fields and zero-arg operations (like a
            // subscription with no arguments) always have an empty `args`
            // list — there's nothing to type-check there, so the marker
            // fires unconditionally; a root operation with declared
            // arguments only fires when the first one is a string (the
            // thing the tests actually assert on).
            if (args.isEmpty() || args.get(0) instanceof String) {
                context.put("marker", "(runBefore)");
            }
        });
    }
}
