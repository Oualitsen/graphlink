import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
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
    "Long": "Long",
    "void": "void"
  };

  test("Controller method should serialize annotations", () {
    final g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
      directive @preAuthorize(value: String, gqAnnotation: Boolean = true, gqOnServer: boolean = true, gqClass: String! = "PreAuthorize", gqImport: String! = "org.springframework.security.access.prepost.PreAuthorize") on FIELD_DEFINITION
      type Person {
        id: ID!
        name: String!
      }
      type Query {
        getPerson(id: String): Person ${gqServiceName}(${gqServiceNameArg}: "PersonService") @preAuthorize(value: "hasRole('USER')") 
      }
    ''');
    expect(parsed is Success, isTrue);
    // this line is needed for the test to pass! do not remote it.
    var personServiceController = g.controllers['PersonServiceController']!;

    // needed for converting controller's annotations to decorators
    SpringServerSerializer(g).serializeController(personServiceController, "com.myorg");
    expect(personServiceController.getImports(g),
        containsAll(['org.springframework.security.access.prepost.PreAuthorize']));
    var getPerson = personServiceController.getFieldByName('getPerson')!;

    var preAuth = getPerson.getDirectives().where((e) => e.token == gqDecorators).toList();
    String value = (preAuth.first.getArgValue("value") as List<String>).first;

    expect(value, '''"@PreAuthorize(value = "hasRole('USER')")"''');
  });
}
