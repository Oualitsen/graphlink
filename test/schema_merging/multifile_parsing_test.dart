import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar_io.dart' as grammar_io;
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("multiple file parsing 1", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    final GLGrammar g = GLGrammar();
    final file = await grammar_io.readLogicalFile(fileName);
    expect(() => grammar_io.parseFile(g, file, validate: true),
        throwsA(isA<ParseException>()));
    final GLGrammar g2 = GLGrammar();
    var parsed = grammar_io.parseFile(g2, file, validate: false);
    expect(parsed is Success, true);
  });

  test("multiple file parsing 2", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    const fileName2 = "test/multifile_parsing/schema2.graphql";
    final GLGrammar g = GLGrammar();
    final files = await Future.wait([
      grammar_io.readLogicalFile(fileName),
      grammar_io.readLogicalFile(fileName2),
    ]);

    var parsed = grammar_io.parseFiles(g, files);
    expect(parsed.length, 2);
    for (var e in parsed) {
      expect(e is Success, true);
    }
    expect(g.inputs.keys, containsAll(["UserInput", "AddressInput"]));
    expect(g.types.keys, containsAll(["User", "Address"]));
  });

  test("merging Query, Mutation and Subscription types 2", () async {
    const fileName = "test/multifile_parsing/schema_with_queries1.graphql";
    const fileName2 = "test/multifile_parsing/schema_with_queries2.graphql";
    final GLGrammar g = GLGrammar();
    final files = await Future.wait([
      grammar_io.readLogicalFile(fileName),
      grammar_io.readLogicalFile(fileName2),
    ]);

    var parsed = grammar_io.parseFiles(g, files);
    expect(parsed.length, 2);
    for (var e in parsed) {
      expect(e is Success, true);
    }
    var query = g.getTypeByName("Query")!;
    var mutation = g.getTypeByName("Mutation")!;
    var subscription = g.getTypeByName("Subscription")!;

    expect(query.fieldNames, containsAll(["getUser", "getCar", "countCars"]));
    expect(mutation.fieldNames, containsAll(["createUser", "creatCar"]));
    expect(subscription.fieldNames, containsAll(["watchUser", "watchCar"]));
  });

  test("fail on merging other than Query, Mutation and Subscription types",
      () async {
    final GLGrammar g = GLGrammar();

    expect(() => g.parse('''
  type User {
    id: String!
  }

  type User {
    name: String!
  }

'''), throwsA(isA<ParseException>()));
  });

  test("fail on merging same field", () async {
    final GLGrammar g = GLGrammar();

    expect(() => g.parse('''
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
