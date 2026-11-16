/// Emitted once per Spring server whose schema has subscriptions. A subscription executed over plain HTTP
/// returns the serialized `Flux` as a 200; this interceptor refuses it unless the transport is a WebSocket
/// or the client asked for server-sent events.
const springSubscriptionTransportConfigFileName = 'GraphLinkSubscriptionTransportConfig.java';

const springSubscriptionTransportConfigSource = '''
import java.util.List;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.graphql.server.WebGraphQlRequest;
import org.springframework.graphql.server.WebGraphQlResponse;
import org.springframework.graphql.server.WebSocketGraphQlRequest;
import org.springframework.graphql.support.DefaultExecutionGraphQlResponse;

import graphql.ExecutionResult;
import graphql.GraphqlErrorBuilder;
import graphql.language.Document;
import graphql.language.OperationDefinition;
import graphql.parser.Parser;

@Configuration
public class GraphLinkSubscriptionTransportConfig {

   @Bean
   public WebGraphQlInterceptor subscriptionsNeedAStreamingTransport() {
      return (request, chain) -> {
         if (isSubscription(request) && !streams(request)) {
            ExecutionResult refused = ExecutionResult.newExecutionResult()
               .addError(GraphqlErrorBuilder.newError()
                  .message("Subscriptions need a WebSocket or an SSE connection")
                  .build())
               .build();
            return reactor.core.publisher.Mono.just(new WebGraphQlResponse(new DefaultExecutionGraphQlResponse(request.toExecutionInput(), refused)));
         }
         return chain.next(request);
      };
   }

   private static boolean streams(WebGraphQlRequest request) {
      if (request instanceof WebSocketGraphQlRequest) {
         return true;
      }
      List<String> accept = request.getHeaders().get("Accept");
      return accept != null && accept.stream().anyMatch(value -> value.contains("text/event-stream"));
   }

   private static boolean isSubscription(WebGraphQlRequest request) {
      try {
         Document document = new Parser().parseDocument(request.getDocument());
         String name = request.getOperationName();
         return document.getDefinitionsOfType(OperationDefinition.class).stream()
            .filter(operation -> name == null || name.equals(operation.getName()))
            .anyMatch(operation -> operation.getOperation() == OperationDefinition.Operation.SUBSCRIPTION);
      } catch (RuntimeException e) {
         return false;
      }
   }
}
''';
