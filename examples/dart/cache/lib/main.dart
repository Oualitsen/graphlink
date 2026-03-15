import 'package:graphlink_cache_example/generated/inputs/create_car_input.dart';
import 'package:graphlink_cache_example/generated/inputs/create_owner_input.dart';
import 'package:http/http.dart' as http;
import 'package:graphlink_cache_example/generated/client/GQClient.dart';

const _serverUrl = 'http://localhost:8080/graphql';

Future<String> graphqlAdapter(String payload) async {
  final response = await http.post(
    Uri.parse(_serverUrl),
    headers: {'Content-Type': 'application/json'},
    body: payload,
  );
  if (response.statusCode != 200) {
    throw Exception('Server error: ${response.statusCode} ${response.body}');
  }
  return response.body;
}

void main(List<String> args) async {
  final client = GQClient(graphqlAdapter, null);

  // Create an owner
  final ownerResponse = await client.mutations.createOwner(
    input: CreateOwnerInput(name: 'John Doe', email: 'john@example.com'),
  );
  var owner = ownerResponse.createOwner;
  print('Created owner: ${owner.id} - ${owner.name}');

  // Create a car for that owner
  final carResponse = await client.mutations.createCar(
    input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023, ownerId: owner.id),
  );
  var car = carResponse.createCar;
  print('Created car: ${car.id} - ${car.make} ${car.model}');

  // Query both together
  final result = await client.queries.getCarAndOwner(carId: car.id, ownerId: owner.id);
  print('getCarAndOwner result: ${result.toJson()}');
  var result2 = await client.queries.getCarAndOwner(carId: car.id, ownerId: owner.id);
  print('getCarAndOwner result: ${result2.toJson()}');
}
