import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("Empty Array value test", () {
    var parser = g.buildFrom(g.arrayValue().end());
    var result = parser.parse("""[]""");
    expect(result.isSuccess, true);
  });

  test("One element Array value test", () {
    var parser = g.buildFrom(g.arrayValue().end());
    var result = parser.parse("""[1]""");
    expect(result.isSuccess, true);
  });

  test("Array values test", () {
    var parser = g.buildFrom(g.arrayValue().end());
    var result = parser.parse("""[]""");
    expect(result.isSuccess, true);

    result = parser.parse("""[{
      test: "hello"
      azul: 12
    }]""");
    expect(result.isSuccess, true);

    result = parser.parse("""[1,2,3,4]""");
    expect(result.isSuccess, true);

    result = parser.parse("""[{
      test: "hello"
      azul: 12
      fast: true
      object: {
        azul: 12
        fast: true
      }
    }, "Azul", "Fellawen"]""");
    expect(result.isSuccess, true);
  });

  test("Object value test", () {
    var parser = g.buildFrom(g.objectValue().end());
    var result = parser.parse("""{
      
    }""");
    expect(result.isSuccess, true);

    result = parser.parse("""{
      test: "hello"
      azul: 12
    }""");
    expect(result.isSuccess, true);

    result = parser.parse("""{
      test: "hello"
      azul: 12
      fast: true
    }""");
    expect(result.isSuccess, true);

    result = parser.parse("""{
      test: "hello"
      azul: 12
      fast: true
      object: {
        azul: 12
        fast: true
      }
    }""");
    expect(result.isSuccess, true);
  });

  test("Argument test", () {
    var parser = g.buildFrom(g.oneArgumentDefinition().end());
    var result = parser.parse("izan: int hello () ");
    expect(result.isSuccess, false);
    result = parser.parse("izan: int!");
    expect(result.isSuccess, true);

    result = parser.parse("izan: int! = 12");
    expect(result.isSuccess, true);
  });

  test("Comment test", () {
    var parser = g.buildFrom(g.singleLineComment());
    var result = parser.parse('''#Comment
    ''');

    expect(result.isSuccess, true);
  });

  test("identifier test", () {
    var parser = g.buildFrom(g.identifier());
    var result = parser.parse(''' test12 ''');
    expect(result.isSuccess, true);
    result = parser.parse(''' 1test ''');
    expect(result.isSuccess, false);
  });

  test("initialValue", () {
    var parser = g.buildFrom(g.initialValue().end());
    var result = parser.parse('''12''');

    expect(result.isSuccess, true);

    result = parser.parse('''12.12''');
    expect(result.isSuccess, true);

    result = parser.parse('''"String value"''');
    expect(result.isSuccess, true);

    result = parser.parse(''' true ''');
    expect(result.isSuccess, true);

    result = parser.parse('''false''');
    expect(result.isSuccess, true);

    result = parser.parse('''
    """
      Block
      String
       """
       ''');
    expect(result.isSuccess, true);
  });

  test("initialize Value", () {
    var parser = g.buildFrom(g.initialization().end());
    var result = parser.parse('''=12''');

    expect(result.isSuccess, true);

    result = parser.parse(''' = 12.12''');
    expect(result.isSuccess, true);

    result = parser.parse('''
     = "String value" #test
     ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' = true ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' = false''');
    expect(result.isSuccess, true);

    result = parser.parse('''=
    """
      Block
      String
       """
       ''');
    expect(result.isSuccess, true);
  });

  test("arguments Value", () {
    var parser = g.buildFrom(g.arguments().end());
    var result = parser.parse('''
    (test: String! = "hello", test2: Int = 3)
       ''');
    expect(result.isSuccess, true);
  });

  test("argumentValues Test", () {
    var parser = g.buildFrom(g.argumentValues().end());
    var result = parser.parse('''
    (test:  "hello", test2:  3)
       ''');
    expect(result.isSuccess, true);
  });

  test("Parametrized argument Test", () {
    var parser = g.buildFrom(g.parametrizedArgument().end());
    var result = parser.parse('''\$azul''');
    expect(result.isSuccess, true);

    result = parser.parse('''azul''');
    expect(result.isSuccess, false);
  });
}
