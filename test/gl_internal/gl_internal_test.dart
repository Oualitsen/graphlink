import 'package:graphlink/src/constants.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test(
      "should not generate all_field_framents on client objects such as GraphLinkPayload",
      () {
    final GLParser g = GLParser(
      nullableFieldsRequired: false,
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
    );
    g.parse('''
${getClientObjects('dynamic', 'Map<String, dynamic>')}

  type Person {
    name: String
  }
  type Query {
    getPerson: Person
  }
''');

    expect(
        g.fragments.keys.where((e) => e.startsWith('_all_fields_GQ')), isEmpty);
  });
}
