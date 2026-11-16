const springSourceSupportFileName = 'GraphLinkSource.java';

const springSourceSupportSource = '''
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Function;

/** Keeps the object a service returned next to its map, so a schema mapping gets that same instance. */
public final class GraphLinkSource {
   public static final String KEY = "__glSource__";

   private GraphLinkSource() {}

   public static Map<String, Object> attach(Map<String, Object> json, Object source) {
      Map<String, Object> carrier = new LinkedHashMap<>(json);
      carrier.put(KEY, source);
      return carrier;
   }

   public static <T> T of(Map<String, Object> json, Class<T> type, Function<Map<String, Object>, T> fromJson) {
      Object source = json.get(KEY);
      return type.isInstance(source) ? type.cast(source) : fromJson.apply(json);
   }
}
''';
