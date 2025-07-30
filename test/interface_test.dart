import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("Implements fields", () {
    var parser = g.buildFrom(g.implementsToken().end());
    var result = parser.parse('''
      implements UserBase & BasicEntity
    ''');
    expect(result is Success, true);
  });

  test("Interface  test", () {
    var parser = g.buildFrom(g.interfaceDefinition().end());
    var result = parser.parse('''
      interface Test implements BasicEntity & UserBase & UserBase2 @skip(if: true) {
        test: boolean! 
        test2: boolean! 
        test3: boolean! 
        test4: boolean! 
      }
    ''');
    expect(result is Success, true);
  });

  test("Interface  list test", () {
    var parser = g.buildFrom(g.interfaceList().end());
    var result = parser.parse('''
       BasicEntity  
    ''');
    expect(result is Success, true);
  });

  test("Interface  list test multiple", () {
    var parser = g.buildFrom(g.interfaceList().end());
    var result = parser.parse('''
       BasicEntity & UserBase & UserBase2 
    ''');
    expect(result.value.length, 3);
    expect(result is Success, true);
  });
}
