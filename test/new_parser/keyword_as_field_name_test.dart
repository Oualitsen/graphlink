import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — keyword as field name', () {
    test('field named "query" in input parses successfully', () {
      final parser = GLParser();
      parser.parse('input UserInput { query: String!, age: Int! }',
          validate: false);
      expect(parser.inputs.containsKey('UserInput'), true);
      expect(parser.inputs['UserInput']!.fields.length, 2);
      expect(parser.inputs['UserInput']!.fields.first.name.token, 'query');
    });
  });
}
