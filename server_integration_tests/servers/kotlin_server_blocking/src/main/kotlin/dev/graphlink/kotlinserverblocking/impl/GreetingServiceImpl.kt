package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.GreetingService
import dev.graphlink.kotlinserverblocking.generated.types.Greeting
import graphql.GraphQLContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.map
import org.springframework.stereotype.Service

@Service
class GreetingServiceImpl : GreetingService {
    private val greetingReceivedFlow = MutableSharedFlow<Greeting>(extraBufferCapacity = 16)

    private fun buildGreeting(name: String, marker: String?): Greeting =
        Greeting(id = "1", message = "Hello, $name${marker ?: ""}")

    override fun greetIntercepted(name: String, graphQLContext: GraphQLContext): Greeting =
        buildGreeting(name, graphQLContext.get("marker"))

    override fun greetPlain(name: String): Greeting = buildGreeting(name, null)

    override fun sendGreeting(name: String): Greeting {
        val greeting = buildGreeting(name, null)
        greetingReceivedFlow.tryEmit(greeting)
        return greeting
    }

    // `runBefore` has already completed by the time this method runs — the
    // generated controller calls it first — so the marker is captured once,
    // here, and baked into every subsequently emitted greeting for the
    // lifetime of this subscription.
    override fun greetingReceived(graphQLContext: GraphQLContext): Flow<Greeting> {
        val marker: String? = graphQLContext.get("marker")
        return greetingReceivedFlow.map { g -> if (marker != null) g.copy(message = g.message + marker) else g }
    }
}
