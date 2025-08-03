import 'package:petitparser/petitparser.dart';

class TokenInfo {
  final int column;
  final int line;
  final String token;
  final String? fileName;

  TokenInfo({required String token, required this.line, required this.column, this.fileName}): token = token.trim();

  static TokenInfo of(Token token, String? fileName) {
    return TokenInfo(token: token.value, line: token.line, column: token.column, fileName: fileName);
  }

  static TokenInfo ofString(String token) {
    return TokenInfo(token: token, line: -1, column: -1);
  }
  
   TokenInfo ofNewName(String token) {
    return TokenInfo(token: token, line: line, column: column, fileName: fileName);
  }

  @override
  String toString() {
    return token;
  }
}