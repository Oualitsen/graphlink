import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';

abstract class GLToken {
  final TokenInfo tokenInfo;
  GLToken(this.tokenInfo);
  String get token => tokenInfo.token;

  final Set<String> _staticImports = {};

  Set<String> get staticImports => Set.unmodifiable(_staticImports);

  void addImport(String import) {
    _staticImports.add(import);
  }

  Set<String> getImports(GLParser g) {
    return staticImports;
  }

  Set<GLToken> getImportDependecies(GLParser g) {
    return Set.unmodifiable([]);
  }
}

abstract class GLExtensibleToken extends GLToken {
  final bool extension;
  final String? documentation;
  GLExtensibleToken(super.tokenInfo, this.extension, {this.documentation});

  void merge<T extends GLExtensibleToken>(T other);
}

class GLExtensibleTokenList {
  final List<GLExtensibleToken> _data = [];
  bool parsedOriginal = false;

  void addToken(GLExtensibleToken token) {
    _data.add(token);
    if (!token.extension) {
      parsedOriginal = true;
    }
  }

  List<GLExtensibleToken> get data => List.unmodifiable(_data);
}
