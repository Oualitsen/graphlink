const graphLinkCacheStore = '''
public interface GraphLinkCacheStore {
    void set(String key, String value);
    String get(String key);
    void invalidate(String key);
    void invalidateAll();
}
''';

const inMemoryGraphLinkCacheStore = '''
public class InMemoryGraphLinkCacheStore implements GraphLinkCacheStore {
    private final ConcurrentHashMap<String, String> store = new ConcurrentHashMap<>();

    public void set(String key, String value) { store.put(key, value); }
    public String get(String key) { return store.get(key); }
    public void invalidate(String key) { store.remove(key); }
    public void invalidateAll() { store.clear(); }
}
''';

const cacheEntry = '''
public class GraphLinkCacheEntry {
    final String data;
    final long expiry;
    final boolean stale;

    GraphLinkCacheEntry(String data, long expiry) {
        this.data = data;
        this.expiry = expiry;
        this.stale = false;
    }

    private GraphLinkCacheEntry(String data, long expiry, boolean stale) {
        this.data = data;
        this.expiry = expiry;
        this.stale = stale;
    }

    static GraphLinkCacheEntry fromJson(Map<String, Object> json) {
        return new GraphLinkCacheEntry(
            (String) json.get("data"),
            ((Number) json.get("expiry")).longValue()
        );
    }

    Map<String, Object> toJson() {
        Map<String, Object> map = new HashMap<>();
        map.put("data", data);
        map.put("expiry", expiry);
        return map;
    }

    boolean isExpired() {
        return System.currentTimeMillis() > expiry;
    }

    GraphLinkCacheEntry asStale() {
        return new GraphLinkCacheEntry(data, expiry, true);
    }
}
''';

const tagEntry = '''
public class GraphLinkTagEntry {
    final Set<String> keys = new HashSet<>();

    GraphLinkTagEntry(Set<String> keys) {
        this.keys.addAll(keys);
    }

    static GraphLinkTagEntry fromJson(Map<String, Object> json) {
        List<?> rawKeys = (List<?>) json.get("keys");
        Set<String> keys = new HashSet<>();
        for (Object k : rawKeys) keys.add((String) k);
        return new GraphLinkTagEntry(keys);
    }

    Map<String, Object> toJson() {
        Map<String, Object> map = new HashMap<>();
        map.put("keys", new ArrayList<>(keys));
        return map;
    }

    void add(String key) { keys.add(key); }
    void remove(String key) { keys.remove(key); }
}
''';

const partialQuery = '''
public class GraphLinkPartialQuery {
    final String query;
    final Map<String, Object> variables;
    final int ttl;
    final List<String> tags;
    final String operationName;
    final String elementKey;
    final Set<String> fragmentNames;
    final List<String> argumentDeclarations;
    final boolean staleIfOffline;
    final String cacheKey;

    GraphLinkPartialQuery(
            String query,
            Map<String, Object> variables,
            int ttl,
            List<String> tags,
            String operationName,
            String elementKey,
            Set<String> fragmentNames,
            List<String> argumentDeclarations,
            boolean staleIfOffline,
            GraphLinkJsonEncoder encoder) {
        this.query = query;
        this.variables = variables;
        this.ttl = ttl;
        this.tags = tags;
        this.operationName = operationName;
        this.elementKey = elementKey;
        this.fragmentNames = fragmentNames;
        this.argumentDeclarations = argumentDeclarations;
        this.staleIfOffline = staleIfOffline;
        this.cacheKey = ttl == 0 ? null : computeCacheKey(operationName, variables, encoder);
    }

    static String computeCacheKey(String operationName, Map<String, Object> variables, GraphLinkJsonEncoder encoder) {
        String raw = operationName + ":" + encoder.encode(new TreeMap<>(variables));
        return fnv1a(raw);
    }

    private static String fnv1a(String input) {
        long hash = 0xcbf29ce484222325L;
        for (char c : input.toCharArray()) {
            hash ^= c;
            hash *= 0x100000001b3L;
        }
        return String.format("%016x", hash);
    }
}
''';
