
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';

void main() async {
  
   test("input reference check (AddressInput) is not defined", () async {
    final GQGrammar g = GQGrammar();
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
    final GQGrammar g = GQGrammar();
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
    final GQGrammar g = GQGrammar();
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
   
