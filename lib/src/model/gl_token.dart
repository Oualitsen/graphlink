import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';

abstract class GLToken {
  final TokenInfo tokenInfo;
  GLToken(this.tokenInfo);
  String get token => tokenInfo.token;

  // Lazily allocated: the vast majority of tokens never receive an import, so
  // we avoid allocating an empty Set per GLToken (one per GLType, argument,
  // directive value, query element, …) across a large schema.
  Set<String>? _staticImports;

  Set<String> get staticImports =>
      _staticImports == null ? const {} : Set.unmodifiable(_staticImports!);

  void addImport(String import) {
    (_staticImports ??= {}).add(import);
  }

  Set<String> getImports(GLParser g) {
    return staticImports;
  }

  Set<GLToken> getImportDependecies(GLParser g) {
    return const {};
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
