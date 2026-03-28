import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("Enum init test", () {
    final g = GLParser();

    g.parse('''
      enum Gender  {
        male female
      }
      type Query {
        getGender(value: Gender! = male): Gender
      }
    ''');
  });
}
