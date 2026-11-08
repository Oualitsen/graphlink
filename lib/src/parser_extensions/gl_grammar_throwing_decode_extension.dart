import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarThrowingDecodeExtension on GLParser {
  /// Whether decoding a value of [typeToken] from JSON can fail on the wire data: every object,
  /// input, interface and union validates the shape of the JSON it reads.
  bool decodesWithThrows(String typeToken) => isProjectableType(typeToken);
}
