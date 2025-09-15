import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

abstract class GQToken {
  final TokenInfo tokenInfo;
  GQToken(this.tokenInfo);
  String get token => tokenInfo.token;

  final Set<String> _staticImports = {};

  Set<String> get staticImports => Set.unmodifiable(_staticImports);

  void addImport(String import) {
    _staticImports.add(import);
  }

  Set<String> getImports(GQGrammar g) {
    return staticImports;
  }

  Set<GQToken> getImportDependecies(GQGrammar g) {
    return Set.unmodifiable([]);
  }
}
