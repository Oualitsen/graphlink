import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Query  element", () {
    final GQGrammar g = GQGrammar();

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
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.queryDefinition(GQQueryType.query).end());
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
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.queryDefinition(GQQueryType.mutation).end());
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
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.queryDefinition(GQQueryType.query).end());
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
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.queryDefinition(GQQueryType.subscription).end());
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
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.queryDefinition(GQQueryType.subscription).end());
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
