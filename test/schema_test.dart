import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() {
  test("Schema element  test", () {
    var parser = g.buildFrom(g.schemaElement().end());
    var result = parser.parse('''
      
      mutation: Test2
    
    ''');
    expect(result is Success, true);
    expect(result.value.type, GLQueryType.mutation);
    expect(result.value.name.token, "Test2");
  });

  test("Schema   test", () {
    var parser = g.buildFrom(g.schemaDefinition().end());
    var result = parser.parse('''
      schema {
      mutation: Test2
   #   query: test1
    }
    ''');
    expect(result is Success, true);
  });
}
