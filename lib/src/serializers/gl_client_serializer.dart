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

  // ── Operation-level rendering (abstract) ──────────────────────────────────

  String renderQueryMethod(GLQueryDefinition def);
  String renderMutationMethod(GLQueryDefinition def);
  String renderUploadMutationMethod(GLQueryDefinition def);
  String renderSubscriptionMethod(GLQueryDefinition def);

  /// Iterates all operations of [type] and dispatches to the appropriate
  /// render method. Replaces the per-language dispatch loops.
  List<String> buildOperationMethods(GLQueryType type) {
    return getOperationsForType(type).map((def) {
      if (def.type == GLQueryType.query) return renderQueryMethod(def);
      if (def.type == GLQueryType.subscription) return renderSubscriptionMethod(def);
      return isUploadMutation(def)
          ? renderUploadMutationMethod(def)
          : renderMutationMethod(def);
    }).toList();
  }

  // ── File-level generation (abstract) ──────────────────────────────────────

  GLClassModel generateClient(String importPrefix);

  GLClassModel generateUploadsFile();

  // ── Queries / mutations / subscriptions class generation (abstract) ────────

  GLClassModel? getQueriesClass(String importPrefix);
  GLClassModel? getMutationsClass(String importPrefix);
  GLClassModel? getSubscriptionsClass(String importPrefix);

  /// Dispatches to [getQueriesClass], [getMutationsClass], or
  /// [getSubscriptionsClass] based on [type].
  GLClassModel? getClassForType(GLQueryType type, String importPrefix) {
    switch (type) {
      case GLQueryType.query:
        return getQueriesClass(importPrefix);
      case GLQueryType.mutation:
        return getMutationsClass(importPrefix);
      case GLQueryType.subscription:
        return getSubscriptionsClass(importPrefix);
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

  String serializeImports(GLParser g, String importPrefix) {
    var deps = getImportDependecies(g);
    final set = <String>{};
    for (var dep in deps) {
      var import = serializer.serializeImportToken(dep, importPrefix);
      if (import.isNotEmpty) {
        set.add(import);
      }
    }
    var buffer = StringBuffer();
    set.forEach(buffer.writeln);
    return buffer.toString();
  }
}
