import 'package:graphlink_cache_example/generated/inputs/create_car_input.dart';
import 'package:graphlink_cache_example/generated/inputs/create_owner_input.dart';
import 'package:graphlink_cache_example/generated/client/graph_link_client.dart';

const _serverUrl = 'http://localhost:8080/graphql';
const _wsUrl = '"ws://localhost:8080/graphql"';

Future<void> createAndFetchCars(GraphLinkClient client) async {
  final carIds = <String>[];

  final car1Response = await client.mutations.createCar(
    input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023),
  );
  carIds.add(car1Response.createCar.id);

  final car2Response = await client.mutations.createCar(
    input: CreateCarInput(make: 'Honda', model: 'Civic', year: 2024),
  );
  carIds.add(car2Response.createCar.id);

  for (final requestedId in [...carIds, ...carIds]) {
    final result = await client.queries.getCar(id: requestedId);
    print('Requested ID: $requestedId | Returned ID: ${result.getCar.id}');
  }

  // Test getCarsCount (cached for 60s)
  final countResult1 = await client.queries.getCarsCount();
  print('Cars count (from server): ${countResult1.getCarsCount}');
  final countResult2 = await client.queries.getCarsCount();
  print('Cars count (from cache):  ${countResult2.getCarsCount}');

  // Test getCarName — first call hits the server, second call hits the cache
  final carId = carIds.first;
  print('\n--- getCarName example ---');
  final nameFromServer = await client.queries.getCarName(id: carId);
  print('[server] getCarName($carId) = ${nameFromServer.getCarName}');
  final nameFromCache = await client.queries.getCarName(id: carId);
  print('[cache]  getCarName($carId) = ${nameFromCache.getCarName}');
}

void main(List<String> args) async {
  final client = GraphLinkClient.withHttp(url: _serverUrl, wsUrl: _wsUrl);
  await createAndFetchCars(client);
  // Create an owner
  final ownerResponse = await client.mutations.createOwner(
    input: CreateOwnerInput(name: 'John Doe', email: 'john@example.com'),
  );
  var owner = ownerResponse.createOwner;
  print('Created owner: ${owner.id} - ${owner.name}');

  // Create a car for that owner
  final carResponse = await client.mutations.createCar(
    input: CreateCarInput(
        make: 'Toyota', model: 'Camry', year: 2023, ownerId: owner.id),
  );
  var car = carResponse.createCar;
  print('Created car: ${car.id} - ${car.make} ${car.model}');

  // Query both together
  final result =
      await client.queries.getCarAndOwner(carId: car.id, ownerId: owner.id);
  print('getCarAndOwner result: ${result.toJson()}');
  var result2 =
      await client.queries.getCarAndOwner(carId: car.id, ownerId: owner.id);
  print('getCarAndOwner result: ${result2.toJson()}');
}
