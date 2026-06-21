// Reusable memoization primitives shared across the parser and its extensions.
//
// These replace the hand-rolled `T? xCache;` fields with their repeated
// `if (cache != null) return cache; ... cache = result;` boilerplate. The
// supplier is passed at the call site (rather than at construction) because
// the derivations live in `extension` libraries and call library-private
// helpers that a field initializer in another library cannot reach.

/// A single lazily-computed, memoized value.
///
/// The first [getOrCompute] runs the supplier and stores its result; every
/// later call returns the cached value without recomputing — including when the
/// computed value is `null` (a cached `null` is distinct from "not yet
/// computed", tracked by [isComputed]). Call [reset] to force recomputation.
///
/// ```dart
/// final _sccIds = Lazy<Map<String, int>>();
/// Map<String, int> get sccIds => _sccIds.getOrCompute(_computeSccIds);
/// ```
class Lazy<T> {
  bool _computed = false;
  T? _value;

  /// Whether the value has been computed and cached.
  bool get isComputed => _computed;

  /// Returns the cached value, computing it via [compute] on first access.
  T getOrCompute(T Function() compute) {
    if (!_computed) {
      _value = compute();
      _computed = true;
    }
    return _value as T;
  }

  /// Drops the cached value so the next [getOrCompute] recomputes.
  void reset() {
    _computed = false;
    _value = null;
  }
}

/// A keyed memoization cache: computes and stores a value per key.
///
/// Stored values may themselves be `null`; [containsKey] distinguishes a cached
/// `null` from an absent key, mirroring [Map]. Use [getOrCompute] for the
/// common compute-once pattern, or the `[]` / `[]=` operators when the caller
/// needs to branch on presence before deciding whether to store.
///
/// ```dart
/// final _blocks = LazyMap<String, GLFragmentBlockDefinition?>();
/// final block = _blocks.getOrCompute(typeName, () => buildBlock(typeName));
/// ```
class LazyMap<K, V> {
  final Map<K, V> _store = {};

  /// Whether a value (possibly `null`) has been cached for [key].
  bool containsKey(K key) => _store.containsKey(key);

  /// Returns the cached value for [key], or `null` if absent.
  V? operator [](K key) => _store[key];

  /// Stores [value] under [key].
  void operator []=(K key, V value) => _store[key] = value;

  /// Returns the cached value for [key], computing and storing it via [compute]
  /// on first access.
  V getOrCompute(K key, V Function() compute) =>
      _store.putIfAbsent(key, compute);

  /// Removes every cached entry.
  void clear() => _store.clear();
}
