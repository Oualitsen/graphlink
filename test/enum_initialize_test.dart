import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Enum init test", () {
    final g = GLGrammar();

    var result = g.parse('''
      enum Gender  {
        male female
      }
      type Query {
        getGender(value: Gender! = male): Gender
      }
    ''');
    expect(result is Success, true);
  });
}
