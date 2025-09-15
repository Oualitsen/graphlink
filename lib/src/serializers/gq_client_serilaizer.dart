import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';

abstract class ClientSerilaizer {
  final GqSerializer serializer;

  ClientSerilaizer(this.serializer);

  String generateClient(String importPrefix);

  String classNameFromType(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
        return "GQQueries";
      case GQQueryType.mutation:
        return "GQMutations";
      case GQQueryType.subscription:
        return "GQSubscriptions";
    }
  }

  Set<GQToken> getImportDependecies(GQGrammar g) {
    var payload = g.getTypeByName("GQPayload");
    var error = g.getTypeByName("GQError");
    var result = <GQToken>[if (payload != null) payload, if (error != null) error];
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

  String serializeImports(GQGrammar g, String importPrefix) {
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
