import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';

void main() {
  test("should throw when argument references a type", () {
    var g = GQGrammar();
    var text = '''
type Car {
  name: String
}

type Query {
  createCar(car: Car): Car
}

''';
    expect(() => g.parse(text), throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Car is not a scalar, enum, or input line: 6 column: 3"),
        ),
      ));
  });


  test("should throw when argument references an interface", () {
    var g = GQGrammar();
    var text = '''
interface Car {
  name: String
}

type Query {
  createCar(car: Car): Car
}

''';
    expect(() => g.parse(text), throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Car is not a scalar, enum, or input line: 6 column: 3"),
        ),
      ));
  });
}