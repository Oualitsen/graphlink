const springDomainErrorDir = 'errors';

const javaServerDomainError = r'''
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public abstract class GraphLinkDomainError extends RuntimeException {
  public GraphLinkDomainError(String message) {
    super(message == null ? "" : message);
  }

  public abstract Map<String, Object> toJson();

  public abstract List<String> wireField();

  public abstract List<String> wireRestField();

  public abstract String wireValue();

  public abstract Integer wireStatus();

  public Map<String, Object> graphqlExtensions() {
    Map<String, Object> entry = new LinkedHashMap<>();
    entry.put("extensions", new LinkedHashMap<String, Object>(toJson()));
    setPath(entry, wireField(), wireValue());
    @SuppressWarnings("unchecked")
    Map<String, Object> extensions = (Map<String, Object>) entry.get("extensions");
    return extensions;
  }

  public int restStatus() {
    return wireStatus() == null ? 400 : wireStatus();
  }

  public Map<String, Object> restBody() {
    Map<String, Object> body = new LinkedHashMap<>(toJson());
    body.put("message", getMessage());
    if (wireRestField() != null) {
      setPath(body, wireRestField(), wireValue());
    }
    return body;
  }

  @SuppressWarnings("unchecked")
  private static void setPath(Map<String, Object> target, List<String> path, Object value) {
    Map<String, Object> node = target;
    for (String segment : path.subList(0, path.size() - 1)) {
      Object next = node.get(segment);
      if (!(next instanceof Map)) {
        next = new LinkedHashMap<String, Object>();
        node.put(segment, next);
      }
      node = (Map<String, Object>) next;
    }
    node.put(path.get(path.size() - 1), value);
  }
}
''';

const javaServerDomainErrorResolver = r'''
import graphql.GraphQLError;
import graphql.GraphqlErrorBuilder;
import graphql.schema.DataFetchingEnvironment;
import org.springframework.graphql.execution.DataFetcherExceptionResolverAdapter;
import org.springframework.graphql.execution.ErrorType;
import org.springframework.stereotype.Component;

@Component
public class GraphLinkDomainErrorResolver extends DataFetcherExceptionResolverAdapter {
  @Override
  protected GraphQLError resolveToSingleError(Throwable ex, DataFetchingEnvironment env) {
    if (!(ex instanceof GraphLinkDomainError)) {
      return null;
    }
    GraphLinkDomainError error = (GraphLinkDomainError) ex;
    return GraphqlErrorBuilder.newError(env)
        .errorType(ErrorType.BAD_REQUEST)
        .message(error.getMessage())
        .extensions(error.graphqlExtensions())
        .build();
  }
}
''';

const javaServerDomainErrorAdvice = r'''
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(annotations = RestController.class)
public class GraphLinkDomainErrorAdvice {
  @ExceptionHandler(GraphLinkDomainError.class)
  public ResponseEntity<Map<String, Object>> handle(GraphLinkDomainError error) {
    return ResponseEntity.status(error.restStatus()).contentType(MediaType.APPLICATION_JSON).body(error.restBody());
  }
}
''';

const kotlinServerDomainError = r'''
abstract class GraphLinkDomainError(message: String?) : RuntimeException(message ?: "") {
  abstract fun toJson(): Map<String, Any?>

  abstract fun wireField(): List<String>

  abstract fun wireRestField(): List<String>?

  abstract fun wireValue(): String

  abstract fun wireStatus(): Int?

  fun graphqlExtensions(): Map<String, Any?> {
    val entry = linkedMapOf<String, Any?>("extensions" to LinkedHashMap(toJson()))
    setPath(entry, wireField(), wireValue())
    @Suppress("UNCHECKED_CAST")
    return entry["extensions"] as Map<String, Any?>
  }

  fun restStatus(): Int = wireStatus() ?: 400

  fun restBody(): Map<String, Any?> {
    val body = LinkedHashMap(toJson())
    body["message"] = message
    wireRestField()?.let { setPath(body, it, wireValue()) }
    return body
  }

  @Suppress("UNCHECKED_CAST")
  private fun setPath(target: MutableMap<String, Any?>, path: List<String>, value: Any?) {
    var node = target
    for (segment in path.dropLast(1)) {
      var next = node[segment]
      if (next !is MutableMap<*, *>) {
        next = linkedMapOf<String, Any?>()
        node[segment] = next
      }
      node = next as MutableMap<String, Any?>
    }
    node[path.last()] = value
  }
}
''';

const kotlinServerDomainErrorResolver = r'''
import graphql.GraphQLError
import graphql.GraphqlErrorBuilder
import graphql.schema.DataFetchingEnvironment
import org.springframework.graphql.execution.DataFetcherExceptionResolverAdapter
import org.springframework.graphql.execution.ErrorType
import org.springframework.stereotype.Component

@Component
class GraphLinkDomainErrorResolver : DataFetcherExceptionResolverAdapter() {
  override fun resolveToSingleError(ex: Throwable, env: DataFetchingEnvironment): GraphQLError? {
    if (ex !is GraphLinkDomainError) return null
    return GraphqlErrorBuilder.newError(env)
        .errorType(ErrorType.BAD_REQUEST)
        .message(ex.message)
        .extensions(ex.graphqlExtensions())
        .build()
  }
}
''';

const kotlinServerDomainErrorAdvice = r'''
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice(annotations = [RestController::class])
class GraphLinkDomainErrorAdvice {
  @ExceptionHandler(GraphLinkDomainError::class)
  fun handle(error: GraphLinkDomainError): ResponseEntity<Map<String, Any?>> =
      ResponseEntity.status(error.restStatus()).contentType(MediaType.APPLICATION_JSON).body(error.restBody())
}
''';
