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

  test("Service should contain two methods getPerson and validateGetPerson",
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Person {
        id: ID!
        name: String!
      }
      type Query {
        getPerson: Person ${glServiceName}(${glServiceNameArg}: "PersonService") ${glValidate}
      }
    ''');

    var personService = g.services['PersonService']!;
    expect(personService.fields.length, 2);
    expect(personService.getFieldByName('getPerson'), isNotNull);
    expect(personService.getFieldByName('validateGetPerson'), isNotNull);
  });

  test("Service should serialize validation method as returning void", () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Person {
        id: ID!
        name: String!
      }
      input SearchQuery {
        term: String!
      }
      type Query {
        getPerson(searchQuery: SearchQuery!): Person ${glServiceName}(${glServiceNameArg}: "PersonService") ${glValidate}
      }
    ''');

    var personService = g.services['PersonService']!;
    var springSerializer = SpringServerSerializer(g);
    var serialzedService =
        springSerializer.serializeService(personService, 'com.myorg');

    expect(
        serialzedService
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'Person getPerson(SearchQuery searchQuery);',
          'void validateGetPerson(SearchQuery searchQuery);'
        ]));
  });

  test(
      "Service should serialize validation method as returning void when datafetching is on",
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Person {
        id: ID!
        name: String!
      }
      input SearchQuery {
        term: String!
      }
      type Query {
        getPerson(searchQuery: SearchQuery!): Person ${glServiceName}(${glServiceNameArg}: "PersonService") ${glValidate}
      }
    ''');

    var personService = g.services['PersonService']!;
    var springSerializer = SpringServerSerializer(g, injectDataFetching: true);
    var serialzedService =
        springSerializer.serializeService(personService, 'com.myorg');
    expect(
        serialzedService
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'Person getPerson(SearchQuery searchQuery, DataFetchingEnvironment dataFetchingEnvironment);',
          'void validateGetPerson(SearchQuery searchQuery, DataFetchingEnvironment dataFetchingEnvironment);'
        ]));
  });

  test(
      "Controller method should call validation method before calling target service methods.",
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Person {
        id: ID!
        name: String!
      }
      input SearchQuery {
        term: String!
      }
      type Query {
        getPerson(searchQuery: SearchQuery!): Person ${glServiceName}(${glServiceNameArg}: "PersonService") ${glValidate}
      }
    ''');

    var personController = g.controllers['PersonServiceController']!;
    var springSerializer = SpringServerSerializer(g);
    var serializedController =
        springSerializer.serializeController(personController, 'com.myorg');
    expect(
        serializedController
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'public CompletableFuture<Person> getPerson(@Argument() SearchQuery searchQuery) {',
         
          'return CompletableFuture.supplyAsync(() -> {',
          'personService.validateGetPerson(searchQuery);',
          'return personService.getPerson(searchQuery);',
          '});'
        ]));
  });

  test(
      "Controller method should call validation method before calling target service methods when injectDataFetching on",
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Person {
        id: ID!
        name: String!
      }
      input SearchQuery {
        term: String!
      }
      type Query {
        getPerson(searchQuery: SearchQuery!): Person ${glServiceName}(${glServiceNameArg}: "PersonService") ${glValidate}
      }
    ''');

    var personController = g.controllers['PersonServiceController']!;
    var springSerializer = SpringServerSerializer(g, injectDataFetching: true);
    var serializedController =
        springSerializer.serializeController(personController, 'com.myorg');
    expect(
        serializedController
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'public CompletableFuture<Person> getPerson(@Argument() SearchQuery searchQuery, DataFetchingEnvironment dataFetchingEnvironment) {',
          'return CompletableFuture.supplyAsync(() -> {',
          'personService.validateGetPerson(searchQuery, dataFetchingEnvironment);',
          'return personService.getPerson(searchQuery, dataFetchingEnvironment);',
          '});'
        ]));
  });
}
