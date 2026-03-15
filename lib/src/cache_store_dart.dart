const graphLinkCacheStore = '''abstract class GraphLinkCacheStore {
  Future<void> set(String key, String value);
  Future<String?> get(String key);
  Future<Set<String>> keys();
  Future<void> invalidate(String key);
  Future<void> invalidateAll();
  
}''';

const inMemoryGraphLinkCacheStore =
    '''class InMemoryGraphLinkCacheStore implements GraphLinkCacheStore {
  final _store = <String, String>{};

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<String?> get(String key) async {
    return _store[key];
  }

  @override
  Future<Set<String>> keys() async {
    return _store.keys.toSet();
  }

  @override
  Future<void> invalidate(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> invalidateAll() async {
    _store.clear();
  }
}''';

const partialQuery = '''
class PartialQuery {
  final String query;
  final Map<String, dynamic> variables;
  final int ttl;
  final String? cacheTag;
  final String operationName;
  final String elementKey;
  final Set<String> fragmentNames;
  final List<String> argumentDeclarations;
  late final String? cacheKey;


  PartialQuery({
    required this.query,
    required this.variables,
    required this.ttl,
    required this.cacheTag,
    required this.operationName,
    required this.elementKey,
    required this.fragmentNames,
    required this.argumentDeclarations,
  }) {
    if (ttl == 0) {
      cacheKey = null;
    } else {
      cacheKey = computeCacheKey(operationName, variables);
    }
  }

  static String computeCacheKey(String operationName, Map<String, dynamic> variables) {
    final sorted = Map.fromEntries(
      variables.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final raw = '\$operationName:\${jsonEncode(sorted)}';
    return _fnv1a(raw);
  }

  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    for (final c in input.codeUnits) {
      hash ^= c;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
''';
const cacheEntry = '''
class CacheEntry {
  final String data;
  final int expiry;

  CacheEntry(this.data, this.expiry);

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(json[\'data\'] as String, json[\'expiry\'] as int);
  }

  Map<String, dynamic> toJson() {
    return {\'data\': data, \'expiry\': expiry};
  }

  String encode() => jsonEncode(toJson());

  static CacheEntry decode(String raw) => CacheEntry.fromJson(jsonDecode(raw));

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiry;
}
''';
