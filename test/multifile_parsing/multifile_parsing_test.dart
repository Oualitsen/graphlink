import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar_io.dart' as grammar_io;
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("empty text parsing 1", () {
    final GLParser g = GLParser();
    g.parse("");
  });

  test("parseFile with validate test 1", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    final GLParser g = GLParser();
    final file = await grammar_io.readLogicalFile(fileName);
    expect(() => grammar_io.parseFile(g, file, validate: true),
        throwsA(isA<ParseException>()));
    final GLParser g2 = GLParser();
    grammar_io.parseFile(g2, file, validate: false);
  });

  test("multiple file parsing 3", () async {
    const fileName = "test/multifile_parsing/schema1.graphql";
    const fileName2 = "test/multifile_parsing/schema2.graphql";
    final GLParser g = GLParser();
    final files = await Future.wait([
      grammar_io.readLogicalFile(fileName),
      grammar_io.readLogicalFile(fileName2),
    ]);

    grammar_io.parseFiles(g, files);

    expect(g.inputs.keys, containsAll(["UserInput", "AddressInput"]));
    expect(g.types.keys, containsAll(["User", "Address"]));
  });

  test("merging Query, Mutation and Subscription types 1", () async {
    const fileName = "test/multifile_parsing/schema_with_queries1.graphql";
    const fileName2 = "test/multifile_parsing/schema_with_queries2.graphql";
    final GLParser g = GLParser();
    final files = await Future.wait([
      grammar_io.readLogicalFile(fileName),
      grammar_io.readLogicalFile(fileName2),
    ]);

    grammar_io.parseFiles(g, files);
    var query = g.getTypeByName("Query")!;
    var mutation = g.getTypeByName("Mutation")!;
    var subscription = g.getTypeByName("Subscription")!;

    expect(query.fieldNames, containsAll(["getUser", "getCar", "countCars"]));
    expect(mutation.fieldNames, containsAll(["createUser", "creatCar"]));
    expect(subscription.fieldNames, containsAll(["watchUser", "watchCar"]));
  });

  test("fail on merging other than Query, Mutation and Subscription types",
      () async {
    final GLParser g = GLParser();

    expect(() => g.parse('''
  type User {
    id: String!
  }

  type User {
    name: String!
  }

'''), throwsA(isA<ParseException>()));
  });
}
