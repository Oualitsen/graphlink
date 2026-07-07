import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

void main() {
  test(
      '@glSkipOnServer with no mapTo on a type returned by a query throws '
      'instead of generating a dangling reference to a never-emitted class', () {
    final g = GLParser(mode: CodeGenerationMode.server);

    expect(
      () => g.parse('''
        type Animal {
            name: String
        }
        type Owner {
            name: String
        }

        type Wrapper {
          id: ID!
        }

        type OwnerWithAnimal @glSkipOnServer(batch: false) {
            owner: Owner!
            animal: Animal
        }

        type Query {
            getOwnerWithAnimal: OwnerWithAnimal
        }
      '''),
      throwsA(isA<ParseException>()),
    );
  });
}
