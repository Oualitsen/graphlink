import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("should generate Response when 'type Query' has one field only", () {
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse('''
  type Person {
    id: String
  }

  type Query {
    getPerson: Person
  }

   type Mutation {
    createPerson: Person
  }

  type Subscription {
    watchPerson: Person
  }
  
''');

    expect(
        g.projectedTypes.keys,
        containsAll([
          'GetPersonResponse',
          'CreatePersonResponse',
          'WatchPersonResponse'
        ]));
  });
}
