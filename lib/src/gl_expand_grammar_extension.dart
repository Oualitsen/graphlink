import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// A field that participates in a type-graph cycle, together with the type
/// that declares it.
class CyclicEdge {
  final GLField field;
  final GLTypeDefinition declaringType;
  CyclicEdge(this.field, this.declaringType);
}

extension GLExpandGrammarExtension on GLParser {
  /// Validates every @glExpand directive in the schema.
  /// The `depth` argument must be a non-negative integer (0 is allowed).
  /// Throws [ParseException] if depth is missing when required, not an integer,
  /// or is a negative integer.
  void checkGLExpandDirectives() {
    for (final type in types.values) {
      final directive = type.getDirectiveByName(glExpand);
      if (directive == null) continue;
      final value = directive.getArgValue(glExpandDepth);
      if (value == null) continue; // omitted — defaultExpandDepth is used, valid
      if (value is! int || value < 0) {
        throw ParseException(
          "$glExpand '$glExpandDepth' must be a non-negative integer (>= 0), got '$value'",
          info: directive.tokenInfo,
        );
      }
    }
  }

  /// Client-mode pass: relaxes every cyclic edge on the declared types and
  /// interfaces to nullable, in place. The cyclic relation can always be absent
  /// at depth, so its type contract must be nullable; doing it on the declared
  /// types makes `types[token]`/`interfaces[token]` already carry the
  /// depth-independent shape, so an all-fields projection can reuse the declared
  /// type directly instead of minting a forced-nullable copy.
  ///
  /// Interface fields are relaxed when any implementor closes the same cycle, so
  /// the abstract getter stays assignment-compatible with its implementors.
  /// Lists are relaxed on the outer type only (matching the projection rule).
  void forceCyclicEdgesNullable() {
    for (final type in types.values) {
      for (final field in [...type.fields]) {
        if (!typeRequiresProjection(field.type)) continue;
        if (field.type.nullable) continue;
        if (isFieldCyclic(type.token, field.type.inlineType.token)) {
          type.replaceField(_nullableEdge(field));
        }
      }
    }
    for (final iface in interfaces.values) {
      final impls = getTypesImplementing(iface);
      for (final field in [...iface.fields]) {
        if (!typeRequiresProjection(field.type)) continue;
        if (field.type.nullable) continue;
        final cyclic = impls
            .any((i) => isFieldCyclic(i.token, field.type.inlineType.token));
        if (cyclic) iface.replaceField(_nullableEdge(field));
      }
    }
  }

  GLField _nullableEdge(GLField f) => GLField(
        name: f.name,
        type: GLType.makeNullable(f.type),
        arguments: f.arguments,
        initialValue: f.initialValue,
        documentation: f.documentation,
        directives: f.getDirectives(),
      );

  /// Returns every [CyclicEdge] where the field's target type is in the same
  /// strongly-connected component as the declaring type.
  ///
  /// Empty when the schema's object-type graph is acyclic.
  /// Interface and union targets are expanded to their concrete members:
  /// a field is cyclic if *any* member is in the same SCC as the declaring type.
  List<CyclicEdge> detectCycles() {
    final result = <CyclicEdge>[];
    for (final typeDef in types.values) {
      for (final field in typeDef.fields) {
        if (!typeRequiresProjection(field.type)) continue;
        if (isFieldCyclic(typeDef.token, field.type.inlineType.token)) {
          result.add(CyclicEdge(field, typeDef));
        }
      }
    }
    return result;
  }

  /// True iff [ownerTypeName] and the concrete type(s) behind [fieldTargetName]
  /// are in the same strongly-connected component — i.e. the field closes a cycle.
  /// Interface and union targets are expanded to their members; the field is
  /// considered cyclic if *any* member is in the same SCC as the owner.
  bool isFieldCyclic(String ownerTypeName, String fieldTargetName) {
    final ids = _sccIds;
    final ownerSCCId = ids[ownerTypeName];
    if (ownerSCCId == null) return false;
    return _resolveConcreteTypes(fieldTargetName)
        .any((t) => ids[t] == ownerSCCId);
  }

  /// Concrete object-type names that participate in a cycle — i.e. their SCC
  /// has more than one member, or the type has a self-edge. Used to bound
  /// inline expansion of cyclic fields independently of any traversal order.
  Set<String> get cyclicTypeNames {
    final cached = cyclicTypeNamesCache;
    if (cached != null) return cached;
    final ids = _sccIds;
    final graph = _buildTypeGraph();
    final sizeById = <int, int>{};
    for (final id in ids.values) {
      sizeById[id] = (sizeById[id] ?? 0) + 1;
    }
    final result = <String>{};
    ids.forEach((name, id) {
      if ((sizeById[id] ?? 0) > 1 || (graph[name]?.contains(name) ?? false)) {
        result.add(name);
      }
    });
    cyclicTypeNamesCache = result;
    return result;
  }

  /// True iff the concrete-target field [fieldName] on [ownerType] is a cycle
  /// back-edge that must be inline-broken in the all-fields fragment (every
  /// other cyclic edge stays a full `_all_fields_<T>` spread). This is the
  /// minimal feedback-edge set, so a chain like `head → project → owner` keeps
  /// all but its closing edge as spreads.
  bool isBackEdgeField(String ownerType, String fieldName) =>
      _cyclicBackEdges.contains('$ownerType.$fieldName');

  /// Deterministic set of cycle back-edges ("OwnerType.fieldName"), found with a
  /// single DFS over the concrete-type graph. Interface/union fields are
  /// traversed through their concrete members so a back-edge that closes through
  /// an abstract type is still attributed to the field that actually carries it.
  ///
  /// Concrete-target fields are preferred as the break point: an abstract-typed
  /// field is only recorded as a back-edge when *it* closes the cycle — i.e. one
  /// of its concrete members is already on the traversal stack at the moment the
  /// edge is examined (the on-stack check runs before recursion, so an
  /// interface-/union-*mediated* cycle that also has a concrete back-edge keeps
  /// its abstract `_all_fields_<T>` spread intact). This only fires for the
  /// pathological "abstract-only" cycle whose sole closing edge is abstract;
  /// there [createAllFieldsFragment] inline-breaks the abstract edge via its
  /// concrete members instead of spreading the (would-be cyclic) fragment.
  Set<String> get _cyclicBackEdges {
    final cached = backEdgesCache;
    if (cached != null) return cached;
    final result = <String>{};
    final onStack = <String>{};
    final visited = <String>{};

    void dfs(String typeName) {
      final typeDef = types[typeName];
      if (typeDef == null) return;
      visited.add(typeName);
      onStack.add(typeName);
      for (final field in typeDef.fields) {
        if (!typeRequiresProjection(field.type)) continue;
        final targetName = field.type.inlineType.token;
        for (final ct in _resolveConcreteTypes(targetName)) {
          if (onStack.contains(ct)) {
            // This edge closes a cycle. Record it as the break point — for a
            // concrete field this is the usual feedback edge; for an abstract
            // field it only happens in an abstract-only cycle (no concrete
            // back-edge exists), so the abstract edge must itself be broken.
            result.add('$typeName.${field.name.token}');
          } else if (!visited.contains(ct)) {
            dfs(ct);
          }
        }
      }
      onStack.remove(typeName);
    }

    for (final name in types.keys) {
      if (!visited.contains(name)) dfs(name);
    }
    backEdgesCache = result;
    return result;
  }

  /// Lazily computed and cached per-parser SCC id map.
  Map<String, int> get _sccIds {
    final cached = sccIdsCache;
    if (cached != null) return cached;
    final sccs = _computeSCCs();
    final ids = <String, int>{};
    for (var i = 0; i < sccs.length; i++) {
      for (final name in sccs[i]) ids[name] = i;
    }
    sccIdsCache = ids;
    return ids;
  }

  /// Resolves an object/interface/union name to concrete object type names.
  Set<String> _resolveConcreteTypes(String typeName) {
    if (types.containsKey(typeName)) return {typeName};
    if (interfaces.containsKey(typeName)) {
      return getTypesImplementing(interfaces[typeName]!)
          .map((t) => t.token)
          .toSet();
    }
    if (unions.containsKey(typeName)) {
      return unions[typeName]!.typeNames.map((t) => t.token).toSet();
    }
    return {};
  }

  /// Builds the directed object-type graph used for SCC detection.
  /// Edges follow object-typed fields; lists are unwrapped; interfaces/unions
  /// are expanded to their concrete members.
  Map<String, Set<String>> _buildTypeGraph() {
    final graph = <String, Set<String>>{
      for (final name in types.keys) name: {},
    };
    for (final typeDef in types.values) {
      for (final field in typeDef.fields) {
        if (!typeRequiresProjection(field.type)) continue;
        final targetName = field.type.inlineType.token;
        graph[typeDef.token]!.addAll(_resolveConcreteTypes(targetName));
      }
    }
    return graph;
  }

  /// Tarjan's SCC algorithm over the object-type graph.
  /// Returns every SCC as a set of type names.
  List<Set<String>> _computeSCCs() {
    final graph = _buildTypeGraph();
    final index = <String, int>{};
    final lowlink = <String, int>{};
    final onStack = <String, bool>{};
    final stack = <String>[];
    final sccs = <Set<String>>[];
    var counter = 0;

    void strongconnect(String v) {
      index[v] = counter;
      lowlink[v] = counter;
      counter++;
      stack.add(v);
      onStack[v] = true;

      for (final w in graph[v] ?? <String>{}) {
        if (!index.containsKey(w)) {
          strongconnect(w);
          final wLow = lowlink[w]!;
          if (wLow < lowlink[v]!) lowlink[v] = wLow;
        } else if (onStack[w] == true) {
          final wIdx = index[w]!;
          if (wIdx < lowlink[v]!) lowlink[v] = wIdx;
        }
      }

      if (lowlink[v] == index[v]) {
        final scc = <String>{};
        while (true) {
          final w = stack.removeLast();
          onStack[w] = false;
          scc.add(w);
          if (w == v) break;
        }
        sccs.add(scc);
      }
    }

    for (final v in graph.keys) {
      if (!index.containsKey(v)) strongconnect(v);
    }

    return sccs;
  }
}
