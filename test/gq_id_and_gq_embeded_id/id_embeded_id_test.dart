
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null",
    "Long": "Long"
  };

 

  test("Multiple @gqId/@gqEmbeddedId", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text =
        """
        type User {
          id: ID! @gqId
          name: ID @gqEmbeddedId
        }
        
        """;
    var parser = g.buildFrom(g.fullGrammar().end());
     expect(
      () => parser.parse(text),
      throwsA(
        isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("Multipe fields of type User are annotated with @gqId/@gqEmbeddedId. Entities must have only one field having directive @gqId/@gqEmbeddedId. Fields are: id, name"),
        ),
      ),
    );
  });

 

}