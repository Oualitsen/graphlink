import 'dart:convert';
import 'dart:io';

import 'package:graphlink_cache_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_cache_integration_tests/generated/inputs/create_car_input.dart';
import 'package:graphlink_cache_integration_tests/generated/inputs/create_owner_input.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const _serverUrl = 'http://localhost:8080/graphql';
const _jarPath = 'spring-server/target/graphql-server-0.0.1-SNAPSHOT.jar';

late Process _serverProcess;
int _serverCallCount = 0;
bool _simulateOffline = false;

Future<String> _countingAdapter(String payload) async {
  if (_simulateOffline) throw Exception('Network unreachable');
  _serverCallCount++;
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

Future<void> _waitForServer({int maxAttempts = 30, Duration delay = const Duration(seconds: 1)}) async {
  for (var i = 0; i < maxAttempts; i++) {
    try {
      await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': '{ getCarsCount }'}),
      );
      return;
    } catch (_) {
      await Future.delayed(delay);
    }
  }
  throw Exception('Server did not start in time');
}

void main() {
  late GraphLinkClient client;

  setUpAll(() async {
    _serverProcess = await Process.start('java', ['-jar', _jarPath]);
    _serverProcess.stdout.transform(utf8.decoder).listen((line) => stdout.write('[server] $line'));
    _serverProcess.stderr.transform(utf8.decoder).listen((line) => stderr.write('[server] $line'));
    await _waitForServer();
  });

  tearDownAll(() {
    _serverProcess.kill();
  });

  setUp(() {
    _serverCallCount = 0;
    _simulateOffline = false;
    client = GraphLinkClient(adapter: _countingAdapter);
  });

  test('getCar is served from cache on second call with same id', () async {
    final created = await client.mutations.createCar(
      input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023),
    );
    final carId = created.createCar.id;

    await client.queries.getCar(id: carId);
    final countAfterFirst = _serverCallCount;

    await client.queries.getCar(id: carId);
    final countAfterSecond = _serverCallCount;

    expect(countAfterSecond, equals(countAfterFirst), reason: 'second getCar should hit cache, not the server');
  });

  test('getCar with different ids hits server each time', () async {
    final car1 = await client.mutations.createCar(
      input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023),
    );
    final car2 = await client.mutations.createCar(
      input: CreateCarInput(make: 'Honda', model: 'Civic', year: 2022),
    );

    _serverCallCount = 0;
    await client.queries.getCar(id: car1.createCar.id);
    await client.queries.getCar(id: car2.createCar.id);

    expect(_serverCallCount, equals(2), reason: 'different ids must each go to the server');
  });

  test('getCarAndOwner serves partial result from cache after cars-tag invalidation', () async {
    final createdCar = await client.mutations.createCar(
      input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023),
    );
    final createdOwner = await client.mutations.createOwner(
      input: CreateOwnerInput(name: 'Alice', email: 'alice@example.com'),
    );
    final carId = createdCar.createCar.id;
    final ownerId = createdOwner.createOwner.id;

    // warm up both sub-query caches
    await client.queries.getCarAndOwner(carId: carId, ownerId: ownerId);
    _serverCallCount = 0;

    // fully cached — no network call expected
    await client.queries.getCarAndOwner(carId: carId, ownerId: ownerId);
    expect(_serverCallCount, equals(0), reason: 'both sub-queries should be served from cache');

    // invalidate the "cars" tag — only the car sub-query cache entry is busted
    await client.mutations.createCar(
      input: CreateCarInput(make: 'Honda', model: 'Civic', year: 2022),
    );
    _serverCallCount = 0;

    // partial fetch: car must come from network, getOwner still from cache
    await client.queries.getCarAndOwner(carId: carId, ownerId: ownerId);
    expect(
      _serverCallCount,
      equals(1),
      reason: 'only the car sub-query should hit the server; getOwner is still cached',
    );
  });

  test('getCarStale returns stale data when network fails after cache expires', () async {
    final created = await client.mutations.createCar(
      input: CreateCarInput(make: 'Ford', model: 'Focus', year: 2020),
    );
    final carId = created.createCar.id;

    // warm the cache (TTL = 1 second)
    final fresh = await client.queries.getCarStale(id: carId);
    expect(fresh.getCarStale.id, equals(carId));

    // let the cache entry expire
    await Future.delayed(const Duration(seconds: 2));

    // go offline — staleIfOffline: true should return the expired entry
    _simulateOffline = true;
    final stale = await client.queries.getCarStale(id: carId);
    expect(stale.getCarStale.id, equals(carId));
  });

  test('getCarExpiring throws when network fails after cache expires', () async {
    final created = await client.mutations.createCar(
      input: CreateCarInput(make: 'Ford', model: 'Focus', year: 2020),
    );
    final carId = created.createCar.id;

    // warm the cache (TTL = 1 second)
    await client.queries.getCarExpiring(id: carId);

    // let the cache entry expire
    await Future.delayed(const Duration(seconds: 2));

    // go offline — staleIfOffline defaults to false, so it should throw
    _simulateOffline = true;
    expect(
      () => client.queries.getCarExpiring(id: carId),
      throwsA(anything),
    );
  });

  test('getCar cache is invalidated after createCar mutation', () async {
    final created = await client.mutations.createCar(
      input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023),
    );
    final carId = created.createCar.id;

    await client.queries.getCar(id: carId);
    _serverCallCount = 0;

    // this mutation carries @glCacheInvalidate(tags: ["cars"]) — busts getCar cache
    await client.mutations.createCar(
      input: CreateCarInput(make: 'Honda', model: 'Civic', year: 2022),
    );
    _serverCallCount = 0;
    await client.queries.getCar(id: carId);
    expect(_serverCallCount, equals(1), reason: 'getCar should hit server after cache invalidation');
  });
}
