
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("should generate Response when 'type Query' has one field only", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parsed = g.parse('''
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
    expect(parsed is Success, true);
    expect(g.projectedTypes.keys, containsAll(['GetPersonResponse', 'CreatePersonResponse', 'WatchPersonResponse']));
  });
}