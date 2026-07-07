import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';


void main() {

  test('batch: true with field arguments throws', () {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: true)
      }
      type Vehicle {
        id: String
      }
    ''');
    expect(
      () => JavaSpringServerSerializer(g, packageName: ""),
      throwsA(isA<ParseException>()),
    );
  });

  test('schema mapping with arguments generates correct controller and service',
      () {
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: false)
      }
      type Vehicle {
        id: String
      }
    ''');

    final serializer = JavaSpringServerSerializer(g, packageName: "com.example");
    final ctrl = g.controllers[g.controllerMappingName('User')]!;
    final service = g.services[g.serviceMappingName('User')]!;

    final controllerCode = serializer.serializeController(ctrl);
    final serviceCode = serializer.serializeService(service);

   print(controllerCode);

    // controller: @SchemaMapping with @Argument params and correct service call

    expect(controllerCode, stringContainsInOrder([
'@SchemaMapping(typeName = "User", field = "vehicles")',
'CompletableFuture<List<? extends Map<String, Object>>> vehicles(@Argument() Integer year, @Argument() String category, Map<String, Object> valueAsMap)',
'return CompletableFuture.supplyAsync(() -> {',
'User value = User.fromJson((Map<String, Object>) valueAsMap);',
'return userSchemaMappingsService.userVehicles(year, category, value).stream().map(e0 -> e0.toJson()).collect(Collectors.toList());',
'});',
    ]));

    expect(serviceCode, stringContainsInOrder([
      'List<Vehicle> userVehicles(Integer year, String category, User value);'
    ]));
  });
}
