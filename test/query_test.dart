import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Query  element", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryElement().end());
    var result = parser.parse('''
    adType(id: \$id) @test {
    ...adTypeFields
    }
     ''');
    // print("result.message = ${result.message}");
    expect(result is Success, true);
  });

  test("Query definition test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryDefinition(GLQueryType.query).end());
    var result = parser.parse('''
      
      query AdType(\$id: String!) {
        adType(id: \$id) {
            ...adTypeFields
        }
    }
    
    ''');
    expect(result is Success, true);
  });

  test("Query definition test 2", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryDefinition(GLQueryType.mutation).end());
    var result = parser.parse('''
      
      mutation AdType(\$id: String!) {
        adType(id: \$id, name: "Ramdane") {
            ...adTypeFields
        }
      }
    
    ''');
    expect(result is Success, true);
  });

  test("Query definition test 3", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryDefinition(GLQueryType.query).end());
    var result = parser.parse('''
      
      query AdType(\$id: String!) {
        adType(id: \$id, name: "Ramdane") {
            ...adTypeFields
        }
      }
    
    ''');
    expect(result is Success, true);
  });

  test("Query definition test 4", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryDefinition(GLQueryType.subscription).end());
    var result = parser.parse('''
      subscription AdType(\$id: String!) {
        adType(id: \$id, name: "Ramdane") {
            ...adTypeFields
        }
      }
    
    ''');
    expect(result is Success, true);
  });

  test("subscription test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.queryDefinition(GLQueryType.subscription).end());
    var result = parser.parse('''
      subscription AdType(\$id: String!) {
        adType(id: \$id, name: "Ramdane") {
            ...adTypeFields
        }
         adType(id: \$id, name: "Ramdane") {
            ...adTypeFields
        }
      }
    
    ''');
    expect(result is Success, false);
  });
}
