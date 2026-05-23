import 'package:graphlink/src/model/new_parser/gl_token_type.dart';

class GLLexerToken {
  final GLTokenType type;
  final String value;
  final int offset; // character offset in source string, for line/column lookup
  const GLLexerToken(this.type, this.value, this.offset);
}
