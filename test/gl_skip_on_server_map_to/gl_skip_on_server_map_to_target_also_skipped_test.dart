import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

void main() {
  test('mapTo referencing an existing type that is also @glSkipOnServer throws', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    expect(
      () => g.parse('''
        type Query { getUser: User }

        type User @glSkipOnServer(mapTo: "UserData") {
          name: String
        }

        type UserData @glSkipOnServer {
          name: String
        }
      '''),
      throwsA(isA<ParseException>()),
    );
  });
}
