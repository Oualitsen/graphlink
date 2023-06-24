import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/model/gq_fragment.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Fragment field test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.plainFragmentField().end());
    var result = parser.parse('''
      name
    ''');
    expect(result.isSuccess, true);
    GQProjection value = result.value;
    expect(value.token, "name");
    expect(value.alias, null);
  });

  test("Fragment field with alias test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.plainFragmentField().end());
    var result = parser.parse('''
      
      alias: name
    
    ''');
    expect(result.isSuccess, true);
    var value = result.value;
    expect(value.token, "name");
    expect(value.alias, "alias");
  });

  test("Fragment field with alias test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.plainFragmentField().end());
    var result = parser.parse('''
      
      alias: name {
        id lastUpdate
      }
    
    ''');
    expect(result.isSuccess, true);
    var value = result.value;
    expect(value.token, "name");
    expect(value.alias, "alias");
    expect(value.block == null, false);
  });

  test("inline Fragment ", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.inlineFragment().end());
    var result = parser.parse('''
       ... on BasicEntity {
        id lastUpdate
       }
      
     
    
    ''');
    expect(result.isSuccess, true);
  });

  test("Fragment Value", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentNameValue().end());
    var result = parser.parse('''
       ... fragmentName
    ''');
    expect(result.isSuccess, true);
  });

  test("Inline fragment or fragment value", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentValue().end());
    var result = parser.parse('''
       ... fragmentName
    ''');
    expect(result.isSuccess, true);

    result = parser.parse('''
        ... on BasicEntity {
        id lastUpdate
       }
      
    ''');
    expect(result.isSuccess, true);
  });

  test("fragmentField test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentField().end());
    var result = parser.parse('''
       ... fragmentName
    ''');
    expect(result.isSuccess, true);

    result = parser.parse('''
        ... on BasicEntity {
        id lastUpdate
       }
      
    ''');
    expect(result.isSuccess, true);

    result = parser.parse('''
       alias:name {
       id lastUpdate
       }
      
    ''');
    expect(result.isSuccess, true);
  });

  test("Fragment Definitions 1", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentDefinition().end());
    var result = parser.parse('''
        fragment productFields  on Product @skip(if: true) @include(if: false) {
          id @skip(if: true)  name {
            id
          }
          
          ...frag2
          ... on BasicEntity {
            lastUpdate @skip(if: true)
          }
      }
    ''');
    expect(result.isSuccess, true);
  });

  test("Fragment Definitions 2", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fragmentDefinition().end());
    parser.parse('''
        
       fragment ProductFields  on Product {
          myAliassedId:id  name 
      }
    ''');
    final frag = g.getFragment("ProductFields");
    final name = frag.block.projections["name"]!;
    final id = frag.block.projections["id"]!;
    expect(id.alias, equals("myAliassedId"));
    expect(name.alias, equals(null));
  });

  test("plainFragmentField List Test", () {
    //plainFragmentField()
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.plainFragmentField().plus().end());
    var result = parser.parse('''
          id  
          myAliassedName : FirstName 
          firstName
    ''');
    expect(result.isSuccess, true);
    var value = result.value;
    expect(value[0].alias, equals(null));
    expect(value[1].alias, equals("myAliassedName"));
    expect(value[2].alias, equals(null));
  });
}
