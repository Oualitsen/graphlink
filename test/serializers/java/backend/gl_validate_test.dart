import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

import '../../../test_utils.dart';

void main() {


  test("Service should contain two methods getPerson and validateGetPerson",
      () {
    final g = GLParser(mode: CodeGenerationMode.server);
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
    final g = GLParser(mode: CodeGenerationMode.server);
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
    var springSerializer = JavaSpringServerSerializer(g, packageName: 'com.myorg');
    var serialzedService =
        springSerializer.serializeService(personService);

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
    final g = GLParser(mode: CodeGenerationMode.server);
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
    var springSerializer = JavaSpringServerSerializer(g, injectDataFetching: true, packageName: "myOrg");
    var serialzedService =
        springSerializer.serializeService(personService);
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
    final g = GLParser(mode: CodeGenerationMode.server);
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
    var springSerializer = JavaSpringServerSerializer(g, packageName: "");
    var serializedController =
        springSerializer.serializeController(personController);
    expect(
        serializedController
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'public CompletableFuture<Map<String, Object>> getPerson(@Argument(name = "searchQuery") Map<String, Object> searchQueryAsMap) {',
          'final SearchQuery searchQuery = SearchQuery.fromJson((Map<String, Object>) searchQueryAsMap);',
          'return CompletableFuture.supplyAsync(() -> {',
          'personService.validateGetPerson(searchQuery);',
          "${toServerProjectionName('Person')} __gl_tmp__ = personService.getPerson(searchQuery);",
          'return __gl_tmp__ == null ? null : __gl_tmp__.toJson();',
          '});'
        ]));
  });

  test(
      "Controller method should call validation method before calling target service methods when injectDataFetching on",
      () {
    final g = GLParser(mode: CodeGenerationMode.server);
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
    var springSerializer = JavaSpringServerSerializer(g, injectDataFetching: true, packageName: "myOrg");
    var serializedController =
        springSerializer.serializeController(personController);
        print(serializedController);
    expect(
        serializedController
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
        containsAllInOrder([
          'public CompletableFuture<Map<String, Object>> getPerson(@Argument(name = "searchQuery") Map<String, Object> searchQueryAsMap, DataFetchingEnvironment dataFetchingEnvironment) {',
          'final SearchQuery searchQuery = SearchQuery.fromJson((Map<String, Object>) searchQueryAsMap);',
          'return CompletableFuture.supplyAsync(() -> {',
          'personService.validateGetPerson(searchQuery, dataFetchingEnvironment);',
          "${toServerProjectionName('Person')} __gl_tmp__ = personService.getPerson(searchQuery, dataFetchingEnvironment);",
          'return __gl_tmp__ == null ? null : __gl_tmp__.toJson();',
          '});'
        ]));
  });
}
