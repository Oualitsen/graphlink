import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';

void main() async {
  test("input reference check (AddressInput) is not defined", () async {
    final GLGrammar g = GLGrammar();
    String data = '''
  input UserInput {
    firstName: String!
    lastName: String!
    middleName: String
    address: AddressInput 
}
''';

    expect(() => g.parse(data), throwsA(isA<ParseException>()));
  });

  test("type reference check (Address) is not defined", () async {
    final GLGrammar g = GLGrammar();
    String data = '''
  type User {
    firstName: String!
    lastName: String!
    middleName: String
    address: Address
}
''';

    expect(() => g.parse(data), throwsA(isA<ParseException>()));
  });

  test("interface reference check (Address) is not defined", () async {
    final GLGrammar g = GLGrammar();
    String data = '''
  interface User {
    firstName: String!
    lastName: String!
    middleName: String
    address: Address
}
''';
    expect(() => g.parse(data), throwsA(isA<ParseException>()));
  });
}
