/// Kotlin twin of `springSubscriptionTransportConfigSource`.
const kotlinSubscriptionTransportConfigFileName = 'GraphLinkSubscriptionTransportConfig.kt';

const kotlinSubscriptionTransportConfigSource = '''
import graphql.ExecutionResult
import graphql.GraphqlErrorBuilder
import graphql.language.OperationDefinition
import graphql.parser.Parser
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.graphql.server.WebGraphQlInterceptor
import org.springframework.graphql.server.WebGraphQlRequest
import org.springframework.graphql.server.WebGraphQlResponse
import org.springframework.graphql.server.WebSocketGraphQlRequest
import org.springframework.graphql.support.DefaultExecutionGraphQlResponse
import reactor.core.publisher.Mono

@Configuration
class GraphLinkSubscriptionTransportConfig {

   @Bean
   fun subscriptionsNeedAStreamingTransport(): WebGraphQlInterceptor =
      WebGraphQlInterceptor { request, chain ->
         if (isSubscription(request) && !streams(request)) {
            val refused = ExecutionResult.newExecutionResult()
               .addError(GraphqlErrorBuilder.newError().message("Subscriptions need a WebSocket or an SSE connection").build())
               .build()
            Mono.just(WebGraphQlResponse(DefaultExecutionGraphQlResponse(request.toExecutionInput(), refused)))
         } else {
            chain.next(request)
         }
      }

   private fun streams(request: WebGraphQlRequest): Boolean =
      request is WebSocketGraphQlRequest ||
         (request.headers["Accept"] ?: emptyList()).any { it.contains("text/event-stream") }

   private fun isSubscription(request: WebGraphQlRequest): Boolean =
      try {
         val name = request.operationName
         Parser().parseDocument(request.document).getDefinitionsOfType(OperationDefinition::class.java)
            .filter { name == null || name == it.name }
            .any { it.operation == OperationDefinition.Operation.SUBSCRIPTION }
      } catch (e: RuntimeException) {
         false
      }
}
''';
