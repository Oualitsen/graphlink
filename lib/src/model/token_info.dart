import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer_token.dart';

class TokenInfo {
  final int column;
  final int line;
  final String token;
  final String? fileName;
  final String? sourceLine;

  TokenInfo(
      {required String token,
      required this.line,
      required this.column,
      this.fileName,
      this.sourceLine})
      : token = token.trim();

  static TokenInfo ofLexer(GLLexerToken token, GLLexer lexer) {
    final loc = lexer.locationOf(token.offset);
    return TokenInfo(
        token: token.value,
        line: loc.line,
        column: loc.column,
        fileName: lexer.fileName,
        sourceLine: lexer.lineAt(loc.line));
  }

  static TokenInfo ofString(String token) {
    return TokenInfo(token: token, line: -1, column: -1);
  }

  TokenInfo ofNewName(String token) {
    return TokenInfo(
        token: token,
        line: line,
        column: column,
        fileName: fileName,
        sourceLine: sourceLine);
  }

  @override
  String toString() {
    return token;
  }
}
