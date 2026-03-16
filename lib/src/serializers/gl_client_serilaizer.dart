import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';

abstract class GLClientSerilaizer {
  final GLSerializer serializer;

  GLClientSerilaizer(this.serializer);

  String generateClient(String importPrefix);

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

  Set<GLToken> getImportDependecies(GLGrammar g) {
    var result = <GLToken>[];
    [
      "GraphLinkPayload",
      "GraphLinkError",
      "GraphLinkSubscriptionPayload",
      "GQAckStatus",
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

  String serializeImports(GLGrammar g, String importPrefix) {
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
