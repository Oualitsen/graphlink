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

abstract class GQExtensibleToken extends GQToken {
  final bool extension;
  GQExtensibleToken(super.tokenInfo, this.extension);

  void merge<T extends GQExtensibleToken>(T other);
}

class GQExtensibleTokenList {
  final List<GQExtensibleToken> _data = [];
  bool parsedOriginal = false;

  void addToken(GQExtensibleToken token) {
    _data.add(token);
    if (!token.extension) {
      parsedOriginal = true;
    }
  }

  List<GQExtensibleToken> get data => List.unmodifiable(_data);
}
