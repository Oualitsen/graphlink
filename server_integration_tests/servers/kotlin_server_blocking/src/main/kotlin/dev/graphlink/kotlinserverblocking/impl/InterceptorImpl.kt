package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.enums.GlInterceptorTag
import dev.graphlink.kotlinserverblocking.generated.interfaces.GraphLinkInterceptor
import graphql.GraphQLContext
import org.springframework.stereotype.Component

@Component
class InterceptorImpl : GraphLinkInterceptor {
    override suspend fun runBefore(tag: GlInterceptorTag?, operation: String, args: List<Any>, context: GraphQLContext) {
        // `Team.members(role: String!)` demonstrates the throw-to-deny contract
        // directly: this is the batch-mapping equivalent of the marker approach
        // used everywhere else, but sidesteps the fact that batch mappings can't
        // reliably pass state back through the request context.
        if (operation == "Team.members") {
            val role = args[0]
            if (role != "auth") {
                throw RuntimeException("Access denied: role \"$role\" is not permitted")
            }
            return
        }

        // Mapping/batch fields and zero-arg operations (like a subscription
        // with no arguments) always have an empty `args` list — there's
        // nothing to type-check there, so the marker fires unconditionally;
        // a root operation with declared arguments only fires when the
        // first one is a string (the thing the tests actually assert on).
        if (args.isEmpty() || args[0] is String) {
            context.put("marker", "(runBefore)")
        }
    }
}
