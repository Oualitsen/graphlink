import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';

class GQRepository extends GQInterfaceDefinition {
  GQRepository({
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.directives,
    required super.interfaceNames,
  });

  static GQRepository of(GQInterfaceDefinition iface) {
    return GQRepository(
      name: iface.tokenInfo,
      nameDeclared: iface.nameDeclared,
      fields: iface.fields,
      directives: iface.getDirectives(),
      interfaceNames: iface.interfaceNames,
    );
  }

  @override
  Set<GQToken> getImportDependecies(GQGrammar g) {
    var result = {...super.getImportDependecies(g)};
    var repoDir = getDirectiveByName(gqRepository)!;
    var token1 = _addDepency(g, repoDir.getArgValueAsString(gqType));
    var token2 = _addDepency(g, repoDir.getArgValueAsString(gqIdType));
    result.addAll([if (token1 != null) token1, if (token2 != null) token2]);
    return result;
  }

  @override
  Set<String> getImports(GQGrammar g) {
    var result = {...super.getImports(g)};
    var repoDir = getDirectiveByName(gqRepository)!;
    result.addAll(_extractImports(repoDir.getArgValueAsString(gqType), g));
    result.addAll(_extractImports(repoDir.getArgValueAsString(gqIdType), g));
    return result;
  }

  Set<String> _extractImports(String? key, GQGrammar g) {
    if (key != null) {
      var token = g.getTokenByKey(key);
      if (token is GQDirectivesMixin) {
        return GQTokenWithFields.extractImports(token as GQDirectivesMixin, g.mode);
      }
    }
    return {};
  }

  GQToken? _addDepency(GQGrammar g, String? key) {
    if (key == null) {
      return null;
    }
    var repoTypeToken = g.getTokenByKey(key);
    if (filterDependecy(repoTypeToken, g)) {
      return repoTypeToken;
    }
    return null;
  }
}
