
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("empty text parsing 1", () {
    final GQGrammar g = GQGrammar();
    var parsed = g.parse("");
    expect(parsed is Success, true);
  });

  test("parseFile with validate test 1", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    final GQGrammar g = GQGrammar();
    expect(() async {
      await g.parseFile(fileName, validate: true);
    }, throwsA(isA<ParseException>()));
    final GQGrammar g2 = GQGrammar();
    var parsed = await g2.parseFile(fileName, validate: false);
    expect(parsed is Success, true);
  });

  test("multiple file parsing 3", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    const fileName2 = "test/multifile_parsing/schema2.graphql";
    final GQGrammar g = GQGrammar();
   
    var parsed = await g.parseFiles([fileName, fileName2]);
    expect(parsed.length, 2);
    for (var e in parsed) {
      expect(e is Success, true);
    }
    expect(g.inputs.keys, containsAll(["UserInput", "AddressInput"]));
    expect(g.types.keys, containsAll(["User", "Address"]));
  });


  test("merging Query, Mutation and Subscription types 1", () async {
    const fileName = "test/multifile_parsing/schema_with_queries1.graphql";
    const fileName2 = "test/multifile_parsing/schema_with_queries2.graphql";
    final GQGrammar g = GQGrammar();
   
    var parsed = await g.parseFiles([fileName, fileName2]);
    expect(parsed.length, 2);
    for (var e in parsed) {
      expect(e is Success, true);
    }
    var query = g.getType("Query");
    var mutation = g.getType("Mutation");
    var subscription = g.getType("Subscription");

    expect(query.fieldNames, containsAll(["getUser", "getCar", "countCars"]));
    expect(mutation.fieldNames, containsAll(["createUser", "creatCar"]));
    expect(subscription.fieldNames, containsAll(["watchUser", "watchCar"]));
  });


  test("fail on merging other than Query, Mutation and Subscription types 1", () async {
   
    final GQGrammar g = GQGrammar();
   
    expect (() => g.parse('''
  type User {
    id: String!
  }

  type User {
    name: String!
  }

'''), throwsA(isA<ParseException>()));

  });


  test("fail on merging same field 1", () async {
   
    final GQGrammar g = GQGrammar();
   
    expect (() => g.parse('''
    type User {
      id: String!
    }

    type Query {
      getUser: User!
    }

    type Query {
      getUser(id: String!): User!
    }

'''), throwsA(isA<ParseException>()));

  });


}
