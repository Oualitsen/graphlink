import 'package:retrofit_graphql/src/constants.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("should not generate all_field_framents on client objects such as GQPayload", () {
    final GQGrammar g = GQGrammar(
      nullableFieldsRequired: false,
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
    );
    var parsed = g.parse('''
${clientObjects}

  type Person {
    name: String
  }
  type Query {
    getPerson: Person
  }
''');
    expect(parsed is Success, true);
    expect(g.fragments.keys.where((e) => e.startsWith('_all_fields_GQ')), isEmpty);
  });
}
