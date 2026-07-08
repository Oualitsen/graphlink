import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';


void main() {
  

  GLParser buildParser() {
    final g = GLParser(
        identityFields: ["id"],
        mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();
    g.parse(text);
    return g;
  }

  test("reactive service interface uses Mono/Flux return types", () {
    final g = buildParser();
    final serializer = JavaSpringServerSerializer(g, packageName: "myorg", reactive: true);
    final service = g.services["UserService"]!;
    final result = serializer.serializeService(service);

    print(result);

    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        'public interface UserService {',
        'Mono<User> getUser();',
        'Mono<User> getUserById(String id);',
        'Flux<User> getUsers(String name, String middle);',
        'Mono<Integer> getUserCount();',
        'Flux<User> watchUser(String userId);',
        'Flux<List<Car>> watchCars(String userId);',
        '}',
      ]),
    );
  });

  test("reactive controller chains Mono<Void> validation via .then()", () {
    final g = GLParser( mode: CodeGenerationMode.server);
    g.parse('''
      type Query {
        getCar(id: ID!): Car! @glValidate
      }
      type Car {
        id: ID!
        make: String!
      }
    ''');
    final serializer = JavaSpringServerSerializer(g, packageName: 'com.example', reactive: true);
    final ctrl = g.controllers['CarServiceController']!;
    final result = serializer.serializeController(ctrl);
    print(result);
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@QueryMapping()',
        'public Mono<Map<String, Object>> getCar(@Argument(name = "id") String id) {',
        'return carService.validateGetCar(id).then(Mono.defer(() -> carService.getCar(id).map(__gl_result__ -> __gl_result__.toJson())));',
        '}',
      ]),
    );
    expect(result, isNot(contains("CompletableFuture")));
  });

  test("reactive controller uses Mono/Flux return types without CompletableFuture", () {
    final g = buildParser();
    final serializer = JavaSpringServerSerializer(g, packageName: "myorg", reactive: true);
    final ctrl = g.controllers["UserServiceController"]!;
    final result = serializer.serializeController(ctrl);

    // must NOT contain CompletableFuture anywhere
    expect(result, isNot(contains("CompletableFuture")));
    print(result);
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller()',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping()',
        'public Mono<Map<String, Object>> getUser() {',
        'return userService.getUser().map(__gl_result__ -> __gl_result__ == null ? null : __gl_result__.toJson());',
        '}',
        '@QueryMapping()',
        'public Mono<Map<String, Object>> getUserById(@Argument(name = "id") String id) {',
        'return userService.getUserById(id).map(__gl_result__ -> __gl_result__ == null ? null : __gl_result__.toJson());',
        '}',
        '@QueryMapping()',
        'public Flux<Map<String, Object>> getUsers(@Argument(name = "name") String name, @Argument(name = "middle") String middle) {',
        'return userService.getUsers(name, middle).map(__gl_result__ -> __gl_result__.toJson());',
        '}',
        '@QueryMapping()',
        'public Mono<Integer> getUserCount() {',
        'return userService.getUserCount();',
        '}',
        '@SubscriptionMapping()',
        'public Flux<Map<String, Object>> watchUser(@Argument(name = "userId") String userId) {',
        'return userService.watchUser(userId).map(__gl_result__ -> __gl_result__.toJson());',
        '}',
        '@SubscriptionMapping()',
        'public Flux<List<? extends Map<String, Object>>> watchCars(@Argument(name = "userId") String userId) {',
        'return userService.watchCars(userId).map(__gl_result__ -> __gl_result__.stream().map(e0 -> e0 == null ? null : e0.toJson()).collect(Collectors.toList()));',
        '}',
        '}',
      ]),
    );
  });
}
