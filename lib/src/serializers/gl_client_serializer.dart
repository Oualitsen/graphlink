import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

abstract class GLClientSerializer {
  final GLSerializer serializer;
  final GLGraphqlSerializer gqlSerializer;

  GLParser get _parser => serializer.grammar;

  GLClientSerializer(this.serializer, this.gqlSerializer);

  // ── Schema-level decision helpers ──────────────────────────────────────────

  List<GLQueryDefinition> getOperationsForType(GLQueryType type) =>
      _parser.queries.values
          .where((q) => q.type == type && _parser.hasQueryType(type))
          .toList();

  bool shouldInvalidateAll(GLQueryDefinition def) =>
      def.elements.any((e) => e.cacheInvalidateAll);

  Set<String> getInvalidationTags(GLQueryDefinition def) =>
      def.elements.expand((e) => e.invalidateCacheTags).toSet();

  bool hasFragments(GLQueryDefinition def) => def.fragments(_parser).isNotEmpty;

  Set<GLFragmentDefinitionBase> getFragmentsForDef(GLQueryDefinition def) =>
      def.fragments(_parser);

  bool isUploadMutation(GLQueryDefinition def) =>
      _parser.mutationHasUploads(def);

  List<GLArgumentDefinition> getUploadArgs(GLQueryDefinition def) {
    final uploadNames = _parser.uploadScalarNames;
    return def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
  }

  String serializeQueryString(GLQueryDefinition def) =>
      gqlSerializer.serializeQueryDefinition(def);

  List<DividedQuery> divideQuery(GLQueryDefinition def) =>
      gqlSerializer.divideQueryDefinition(def, _parser);

  String buildQueryString(GLQueryDefinition def) {
    final query = gqlSerializer.serializeQueryDefinition(def);
    final frags = getFragmentsForDef(def)
        .map((f) => gqlSerializer.serializeFragmentDefinitionBase(f))
        .join(' ');
    return frags.isEmpty ? query : '$query $frags';
  }

  // ── Operation-level rendering (abstract) ──────────────────────────────────

  String renderQueryMethod(GLQueryDefinition def);
  String renderMutationMethod(GLQueryDefinition def);
  String renderUploadMutationMethod(GLQueryDefinition def);
  String renderSubscriptionMethod(GLQueryDefinition def);

  late final Set<String> oversizedFragmentNames = {
    if (_parser.maxFragmentBodySize != null)
      for (final f in _parser.usedFragments)
        if (gqlSerializer.serializeFragmentDefinitionBase(f).length >
            _parser.maxFragmentBodySize!)
          f.tokenInfo.token,
  };

  /// Iterates all operations of [type] and dispatches to the appropriate
  /// render method. Skips operations that reference an oversized fragment.
  List<String> buildOperationMethods(GLQueryType type) {
    return getOperationsForType(type)
        .where((def) => !def
            .fragments(_parser)
            .any((f) => oversizedFragmentNames.contains(f.tokenInfo.token)))
        .map((def) {
      if (def.type == GLQueryType.query) return renderQueryMethod(def);
      if (def.type == GLQueryType.subscription) return renderSubscriptionMethod(def);
      return isUploadMutation(def)
          ? renderUploadMutationMethod(def)
          : renderMutationMethod(def);
    }).toList();
  }

  // ── File-level generation (abstract) ──────────────────────────────────────

  GLClassModel generateClient();

  GLClassModel generateUploadsFile();

  // ── Queries / mutations / subscriptions class generation (abstract) ────────

  GLClassModel? getQueriesClass();
  GLClassModel? getMutationsClass();
  GLClassModel? getSubscriptionsClass();

  /// Dispatches to [getQueriesClass], [getMutationsClass], or
  /// [getSubscriptionsClass] based on [type].
  GLClassModel? getClassForType(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return getQueriesClass();
      case GLQueryType.mutation:
        return getMutationsClass();
      case GLQueryType.subscription:
        return getSubscriptionsClass();
    }
  }

  String classNameFromType(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return "GraphLinkQueries";
      case GLQueryType.mutation:
        return "GraphLinkMutations";
      case GLQueryType.subscription:
        return "GraphLinkSubscriptions";
    }
  }

  Set<GLToken> getImportDependecies(GLParser g) {
    var result = <GLToken>[];
    [
      "GraphLinkPayload",
      "GraphLinkError",
      "GraphLinkSubscriptionPayload",
      "GraphLinkAckStatus",
      "GraphLinkSubscriptionErrorMessageBase",
      "GraphLinkSubscriptionErrorMessage",
      "GraphLinkSubscriptionMessage",
      "GraphLinkSubscriptionMessageType",
      "GraphLinkFullResponse"
    ]
        .map(g.getTokenByKey)
        .where((e) => e != null)
        .map((e) => e!)
        .forEach(result.add);
    g.queries.values
        .where((element) => element.typeDefinition != null)
        .map((e) => e.typeDefinition!)
        .forEach(result.add);

    if (g.getTypeByName('GraphLinkError') != null) {
      g.queries.values
          .map((e) => e.getFullResponseTypeDefinition(g))
          .forEach(result.add);
    }

    g.queries.values.expand((e) => e.arguments).forEach((arg) {
      if (g.isEnum(arg.type.token)) {
        result.add(g.enums[arg.type.token]!);
      } else if (g.isInput(arg.type.token)) {
        result.add(g.inputs[arg.type.token]!);
      }
    });

    return Set.unmodifiable(result);
  }

  String serializeImports(GLParser g) {
    var deps = getImportDependecies(g);
    final set = <String>{};
    for (var dep in deps) {
      var import = serializer.serializeImportToken(dep);
      if (import.isNotEmpty) {
        set.add(import);
      }
    }
    var buffer = StringBuffer();
    set.forEach(buffer.writeln);
    return buffer.toString();
  }

  /// Returns the deduplicated [GLToken] set for operations of [type]:
  /// - `GraphLinkPayload` always; `GraphLinkError` for non-subscriptions
  /// - upload / subscription → only `typeDefinition` per op
  /// - `@glCaptureErrors` → only `fullResponse` per op
  /// - plain query/mutation → both `fullResponse` + `typeDefinition`
  /// - enum/input tokens for all operation arguments
  List<GLToken> schemaTokensFor(GLQueryType type) {
    final tokens = <GLToken>[];

    final payload = _parser.getTokenByKey('GraphLinkPayload');
    if (payload != null) tokens.add(payload);

    final ops = _parser.queries.values.where((q) => q.type == type);
    for (final op in ops) {
      if (type == GLQueryType.subscription) {
        final td = op.typeDefinition;
        if (td != null) tokens.add(td);
      } else {
        tokens.add(op.getFullResponseTypeDefinition(_parser));
        if (!op.isCaptureErrors(_parser)) {
          final td = op.typeDefinition;
          if (td != null) tokens.add(td);
        }
      }

      for (final arg in op.arguments) {
        _collectArgTokens(
          arg.type.firstType.token,
          tokens,
          {},
          recurse: arg.defaultValue?.value != null,
        );
      }
    }

    final seen = <String>{};
    return tokens.where((t) => seen.add(t.token)).toList();
  }

  /// Collects enum/input tokens for [typeName].
  /// When [recurse] is true (argument has a non-null default value), also
  /// traverses the input's fields transitively so that types referenced in
  /// the default value expression (e.g. `AuditLogOrderField`) are imported.
  void _collectArgTokens(
    String typeName,
    List<GLToken> out,
    Set<String> visited, {
    bool recurse = false,
  }) {
    if (!visited.add(typeName)) return;
    if (_parser.isEnum(typeName)) {
      final e = _parser.enums[typeName];
      if (e != null) out.add(e);
    } else if (_parser.isInput(typeName)) {
      final i = _parser.inputs[typeName];
      if (i == null) return;
      out.add(i);
      if (recurse) {
        for (final field in i.fields) {
          _collectArgTokens(field.type.firstType.token, out, visited, recurse: true);
        }
      }
    }
  }

  /// Returns import lines scoped to operations of [type].
  /// Converts [schemaTokensFor] tokens to language-specific import strings.
  List<String> schemaImportsFor(GLQueryType type) {
    final seen = <String>{};
    final result = <String>[];
    for (final t in schemaTokensFor(type)) {
      final imp = serializer.serializeImportToken(t);
      if (imp.isNotEmpty && seen.add(imp)) result.add(imp);
    }
    return result;
  }
}
