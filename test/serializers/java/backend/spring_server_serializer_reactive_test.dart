import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
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
    final serializer = SpringServerSerializer(g, reactive: true);
    final service = g.services["UserService"]!;
    final result = serializer.serializeService(service, "myorg");

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
    final serializer = SpringServerSerializer(g, reactive: true);
    final ctrl = g.controllers['CarServiceController']!;
    final result = serializer.serializeController(ctrl, 'com.example');
    print(result);
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@QueryMapping()',
        'public Mono<Car> getCar(@Argument() String id) {',
        'return carService.validateGetCar(id).then(carService.getCar(id));',
        '}',
      ]),
    );
    expect(result, isNot(contains("CompletableFuture")));
  });

  test("reactive controller uses Mono/Flux return types without CompletableFuture", () {
    final g = buildParser();
    final serializer = SpringServerSerializer(g, reactive: true);
    final ctrl = g.controllers["UserServiceController"]!;
    final result = serializer.serializeController(ctrl, "myorg");

    // must NOT contain CompletableFuture anywhere
    expect(result, isNot(contains("CompletableFuture")));

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
        'public Mono<User> getUser() {',
        'return userService.getUser();',
        '}',
        '@QueryMapping()',
        'public Mono<User> getUserById(@Argument() String id) {',
        'return userService.getUserById(id);',
        '}',
        '@QueryMapping()',
        'public Flux<User> getUsers(@Argument() String name, @Argument() String middle) {',
        'return userService.getUsers(name, middle);',
        '}',
        '@QueryMapping()',
        'public Mono<Integer> getUserCount() {',
        'return userService.getUserCount();',
        '}',
        '@SubscriptionMapping()',
        'public Flux<User> watchUser(@Argument() String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping()',
        'public Flux<List<Car>> watchCars(@Argument() String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '}',
      ]),
    );
  });
}
