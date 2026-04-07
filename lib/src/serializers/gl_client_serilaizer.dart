import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

abstract class GLClientSerilaizer {
  final GLSerializer serializer;

  GLClientSerilaizer(this.serializer);

  GLClassModel generateClient(String importPrefix);

  /// Returns the [GLClassModel] for the queries class, or `null` if the
  /// grammar has no queries.
  GLClassModel? getQueriesClass(String importPrefix);

  /// Returns the [GLClassModel] for the mutations class, or `null` if the
  /// grammar has no mutations.
  GLClassModel? getMutationsClass(String importPrefix);

  /// Returns the [GLClassModel] for the subscriptions class, or `null` if the
  /// grammar has no subscriptions.
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
      "GraphLinkSubscriptionMessageType"
    ]
        .map(g.getTokenByKey)
        .where((e) => e != null)
        .map(
          (e) => e!,
        )
        .forEach(result.add);
    g.queries.values
        .where((element) => element.typeDefinition != null)
        .map((e) => e.typeDefinition!)
        .forEach(result.add);

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
    var buffer = StringBuffer();
    var deps = getImportDependecies(g);
    for (var dep in deps) {
      var import = serializer.serializeImportToken(dep, importPrefix);
      if (import.isNotEmpty) {
        buffer.writeln(import);
      }
    }
    return buffer.toString();
  }
}
