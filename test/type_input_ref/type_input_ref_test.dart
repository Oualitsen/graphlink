import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("should throw when argument references a type", () {
    var g = GLParser();
    var text = '''
type Car {
  name: String
}

type Query {
  createCar(car: Car): Car
}

''';
    expect(
        () => g.parse(text),
        throwsA(
          isA<ParseException>().having(
            (e) => e.errorMessage,
            'errorMessage',
            contains("Car is not a scalar, enum, or input line: 6 column: 3"),
          ),
        ));
  });

  test("should throw when argument references an interface", () {
    var g = GLParser();
    var text = '''
interface Car {
  name: String
}

type Query {
  createCar(car: Car): Car
}

''';
    expect(
        () => g.parse(text),
        throwsA(
          isA<ParseException>().having(
            (e) => e.errorMessage,
            'errorMessage',
            contains("Car is not a scalar, enum, or input line: 6 column: 3"),
          ),
        ));
  });
}
