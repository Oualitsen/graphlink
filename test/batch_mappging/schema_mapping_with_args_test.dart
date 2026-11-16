import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java/java_spring_server_serializer.dart';
import 'package:test/test.dart';


void main() {

  test('batch: true with field arguments throws', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: true)
      }
      type Vehicle {
        id: String
      }
    ''');
    expect(
      () => JavaSpringServerSerializer(g, packageName: ""),
      throwsA(isA<ParseException>()),
    );
  });
}
