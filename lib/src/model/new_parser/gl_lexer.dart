import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_lexter_token.dart';
import 'package:graphlink/src/model/new_parser/gl_token_type.dart';
import 'package:graphlink/src/model/token_info.dart';

const _whites = {' ', '\t', ','};
const _newLines = {'\r', '\n'};
const _commentPrefix = '#';
const _digits = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'};
const _whitesAndNewLinesAndComment = {..._whites, ..._newLines, _commentPrefix};

const openBrace = '{';
const closeBrace = '}';
const openParen = '(';
const closeParen = ')';
const openBracket = '[';
const closeBracket = ']';
const colon = ':';
const bang = '!';
const equals = '=';
const pipe = '|';
const at = '@';
const amp = '&';

class GLLexer {
  final String source;
  final String? fileName;
  int _pos = 0;
  final List<int> _lineOffsets = [0]; // offset of the start of each line
  final List<GLLexerToken> tokens = [];

  GLLexer(this.source, {this.fileName});

  List<GLLexerToken> tokenize() {
    while (_pos < source.length) {
      _skipWhitespaceAndComments();
      if (_pos >= source.length) break;
      _scanToken();
    }
    tokens.add(GLLexerToken(GLTokenType.eof, '', _pos));
    return tokens;
  }

  GLTokenLocation locationOf(int offset) {
    int lo = 0, hi = _lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineOffsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return GLTokenLocation(line: lo + 1, column: offset - _lineOffsets[lo] + 1);
  }

  void _skipWhitespaceAndComments() {
    while (source.length > _pos &&
        _whitesAndNewLinesAndComment.contains(source[_pos])) {
      var currentChar = source[_pos];
      if (currentChar == _commentPrefix) {
        // advance until you hit a new line.
        while (source.length > _pos && source[_pos] != '\n') {
          _pos++;
        }
        continue;
      }
      _trackNewLines();
      _pos++;
    }
  }

  void _trackNewLines() {
    if (source.length > _pos && source[_pos] == '\n') {
      _lineOffsets.add(_pos + 1);
    }
  }

  void _scanToken() {
    final current = source[_pos];
    switch (current) {
      case openBrace:
        tokens.add(GLLexerToken(GLTokenType.openBrace, current, _pos++));
        break;
      case closeBrace:
        tokens.add(GLLexerToken(GLTokenType.closeBrace, current, _pos++));
        break;
      case openParen:
        tokens.add(GLLexerToken(GLTokenType.openParen, current, _pos++));
        break;
      case closeParen:
        tokens.add(GLLexerToken(GLTokenType.closeParen, current, _pos++));
        break;
      case openBracket:
        tokens.add(GLLexerToken(GLTokenType.openBracket, current, _pos++));
        break;
      case closeBracket:
        tokens.add(GLLexerToken(GLTokenType.closeBracket, current, _pos++));
        break;
      case colon:
        tokens.add(GLLexerToken(GLTokenType.colon, current, _pos++));
        break;
      case bang:
        tokens.add(GLLexerToken(GLTokenType.bang, current, _pos++));
        break;
      case equals:
        tokens.add(GLLexerToken(GLTokenType.equals, current, _pos++));
        break;
      case pipe:
        tokens.add(GLLexerToken(GLTokenType.pipe, current, _pos++));
        break;
      case at:
        tokens.add(GLLexerToken(GLTokenType.at, current, _pos++));
        break;
      case amp:
        tokens.add(GLLexerToken(GLTokenType.amp, current, _pos++));
        break;
      case r'$':
        _scanDollarIdentifier();
        break;
      case ".":
        _tryReadSpread();
        break;
      case '"':
        _tryReadString();
        break;
      case '-':
      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
        _scanNumber();
        break;
      default:
        if (_isIdentifierChar(source.codeUnitAt(_pos))) {
          _scanIdentifier();
        } else {
          final loc = locationOf(_pos);
          throw ParseException("Unexpected character '${source[_pos]}'",
              info: TokenInfo(
                  token: source[_pos], line: loc.line, column: loc.column));
        }
    }
  }

  bool _isIdentifierChar(int code) =>
      code == 95 ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57);

  void _scanIdentifier() {
    int start = _pos;
    var value = StringBuffer();
    while (!_isEofReached) {
      var current = source[_pos];
      if (_isIdentifierChar(current.codeUnitAt(0))) {
        value.write(current);
      } else {
        break;
      }
      _pos++;
    }

    String valueStr = value.toString();
    tokens.add(GLLexerToken(
        keywords[valueStr] ?? GLTokenType.identifier, value.toString(), start));
  }

  void _scanDollarIdentifier() {
    final start = _pos;
    final value = StringBuffer(source[_pos]); // write '$'
    _pos++;
    if (_isEofReached || !_isIdentifierChar(source.codeUnitAt(_pos))) {
      throw errorAt(start, "Expected identifier after '\$'");
    }
    while (!_isEofReached && _isIdentifierChar(source.codeUnitAt(_pos))) {
      value.write(source[_pos]);
      _pos++;
    }
    tokens.add(GLLexerToken(GLTokenType.identifier, value.toString(), start));
  }

  String _readInt() {
    var result = StringBuffer();
    while (!_isEofReached && _digits.contains(source[_pos])) {
      result.write(source[_pos]);
      _pos++;
    }
    return result.toString();
  }

  String _readExpValue() {
    var result = StringBuffer();
    if (!_isEofReached && _isCurrentExp) {
      result.write(source[_pos]);
      _pos++;

      if (_isEofReached) {
        throw errorAt(_pos, 'Expected digits after exponent');
      }

      // read the optional -
      if (source[_pos] == '-' || source[_pos] == '+') {
        result.write(source[_pos]);
        _pos++;
      }
      var intValue = _readInt();
      if (intValue.isEmpty) {
        throw errorAt(_pos, 'Expected digits after exponent sign');
      }
      result.write(intValue);
    } else {
      throw errorAt(_pos, "Expected 'e' or 'E' for exponent");
    }

    return result.toString();
  }

  bool get _isCurrentExp {
    var current = source[_pos];
    return current == 'e' || current == 'E';
  }

  void _scanNumber() {
    StringBuffer value = StringBuffer();
    int start = _pos;
    bool isFloat = false;
    var current = source[_pos];
    if (current == '-') {
      value.write(current);
      _pos++;
    }
    // read next set of ints
    value.write(_readInt());

    if (_isEofReached) {
      tokens.add(GLLexerToken(GLTokenType.int_, value.toString(), start));
      return;
    }
    current = source[_pos];
    if (current == '.') {
      _pos++;
      isFloat = true;
      value.write(current);
      value.write(_readInt());
      if (!_isEofReached) {
        current = source[_pos];
        //check for the optional E.
        if (_isCurrentExp) {
          isFloat = true;
          value.write(_readExpValue());
        }
      }
    } else if (_isCurrentExp) {
      isFloat = true;
      value.write(_readExpValue());
    }
    tokens.add(GLLexerToken(isFloat ? GLTokenType.float_ : GLTokenType.int_,
        value.toString(), start));
  }

  void _tryReadString() {
    if (_expectStringBlock()) {
      _tryReadStringBlock();
    } else {
      _tryReadSingleLineString();
    }
  }

  void _tryReadSingleLineString() {
    // supposed to read a string while source[_pos] = '"'
    int start = _pos;
    StringBuffer value = StringBuffer(source[_pos]);
    while (true) {
      _pos++;
      if (_isEofReached) {
        throw errorAt(start, 'Unterminated string');
      }
      if (source[_pos] == '\n') {
        throw errorAt(_pos, 'Unexpected newline inside string');
      }
      if (source[_pos] == '\\') {
        //check for the next
        if (source.length > _pos + 1 && source[_pos + 1] == '"') {
          value.write('"');
          _pos++;
          continue;
        } else {
          value.write('\\');
        }
      } else if (source[_pos] == '"') {
        //end of string
        value.write('"');
        _pos++;
        break;
      } else {
        value.write(source[_pos]);
      }
    }
    tokens.add(GLLexerToken(GLTokenType.string, value.toString(), start));
  }

  bool get _isEofReached {
    return _pos >= source.length;
  }

  ParseException errorAt(int offset, String message) {
    final loc = locationOf(offset);
    return ParseException(message,
        info: TokenInfo(
            token: _pos < source.length ? source[_pos] : '',
            line: loc.line,
            column: loc.column,
            fileName: fileName));
  }

  void _tryReadStringBlock() {
    final start = _pos;
    var value = StringBuffer('"""');
    _pos += 3;
    while (true) {
      // look ahead to check the ending of the string block
      if (_isEofReached) {
        throw errorAt(start, 'Unterminated block string, expected \'"""\'');
      }
      _trackNewLines();
      if (source[_pos] == '"' && source.length >= _pos + 3) {
        if (source[_pos + 1] == '"' && source[_pos + 2] == '"') {
          _pos += 3;
          value.write('"""');
          tokens.add(
              GLLexerToken(GLTokenType.blockString, value.toString(), start));
          return;
        }
      }
      value.write(source[_pos]);
      _pos++;
    }
  }

  bool _expectStringBlock() {
    // called only when source[_pos] = '"'
    if (source.length >= _pos + 3) {
      if (source[_pos + 1] == '"' && source[_pos + 2] == '"') {
        return true;
      }
    }
    return false;
  }

  void _tryReadSpread() {
    if (source.length >= _pos + 3 &&
        source[_pos + 1] == "." &&
        source[_pos + 2] == ".") {
      final start = _pos;
      _pos += 3;
      tokens.add(GLLexerToken(GLTokenType.spread, "...", start));
    } else {
      throw errorAt(_pos, "Expected '...' but got '${source[_pos]}'");
    }
  }
}

class GLTokenLocation {
  final int line;
  final int column;
  GLTokenLocation({required this.line, required this.column});
}
