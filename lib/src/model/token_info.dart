import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer_token.dart';

class TokenInfo {
  final int column;
  final int line;
  final String token;
  final String? fileName;

  // Lazy source-line support. Instead of slicing the whole source line out for
  // every token at construction (tens of thousands of retained substrings on a
  // large schema), we keep a reference to the shared source string and the
  // start offset of this token's line. The line is materialized only when an
  // error is actually rendered (parse_exception.dart) — i.e. for ~one token.
  final String? _source;
  final int _lineStart;
  String? _sourceLine;

  TokenInfo(
      {required String token,
      required this.line,
      required this.column,
      this.fileName,
      String? sourceLine,
      String? source,
      int lineStart = 0})
      : token = token.trim(),
        _source = source,
        _lineStart = lineStart,
        _sourceLine = sourceLine;

  /// The full source line this token sits on, computed lazily from the shared
  /// source string. Returns null for synthetic tokens (no source/line).
  String? get sourceLine {
    final cached = _sourceLine;
    if (cached != null) return cached;
    final src = _source;
    if (src == null || line <= 0) return null;
    final end = src.indexOf('\n', _lineStart);
    return _sourceLine =
        end == -1 ? src.substring(_lineStart) : src.substring(_lineStart, end);
  }

  static TokenInfo ofLexer(GLLexerToken token, GLLexer lexer) {
    final loc = lexer.locationOf(token.offset);
    return TokenInfo(
        token: token.value,
        line: loc.line,
        column: loc.column,
        fileName: lexer.fileName,
        source: lexer.source,
        // start of this token's line = token offset minus its (1-based) column.
        lineStart: token.offset - (loc.column - 1));
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
        sourceLine: _sourceLine,
        source: _source,
        lineStart: _lineStart);
  }

  @override
  String toString() {
    return token;
  }
}
