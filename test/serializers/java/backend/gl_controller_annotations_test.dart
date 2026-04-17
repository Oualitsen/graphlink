import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

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
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      directive @preAuthorize(value: String, glAnnotation: Boolean = true, glOnServer: boolean = true, glClass: String! = "PreAuthorize", glImport: String! = "org.springframework.security.access.prepost.PreAuthorize") on FIELD_DEFINITION
      type Person {
        id: ID!
        name: String!
      }
      type Query {
        getPerson(id: String): Person ${glServiceName}(${glServiceNameArg}: "PersonService") @preAuthorize(value: "hasRole('USER')") 
      }
    ''');

    // this line is needed for the test to pass! do not remote it.
    var personServiceController = g.controllers['PersonServiceController']!;

    // needed for converting controller's annotations to decorators
    SpringServerSerializer(g)
        .serializeController(personServiceController, "com.myorg");
    expect(
        personServiceController.getImports(g),
        containsAll(
            ['org.springframework.security.access.prepost.PreAuthorize']));
    var getPerson = personServiceController.getFieldByName('getPerson')!;

    var preAuth = getPerson
        .getDirectives()
        .where((e) => e.token == glDecorators)
        .toList();
    String value = (preAuth.first.getArgValue("value") as List<String>).first;

    expect(value, '''"@PreAuthorize(value = "hasRole('USER')")"''');
  });
}
