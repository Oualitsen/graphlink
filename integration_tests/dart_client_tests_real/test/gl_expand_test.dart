import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:graphlink_client_integration_tests/generated/types/car.dart';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

// Cycle: VehicleDriver → Vehicle (Car|Bike) → VehicleOwner → VehicleDriver
//
// VehicleDriver is annotated @glExpand(depth: 3) in the schema, so the
// auto-generated query recurses 3 hops into the cycle before stopping:
//
//   layer 1 — VehicleDriver.vehicle          (Car or Bike)
//   layer 2 — Car/Bike.owner                 (VehicleOwner)
//   layer 3 — VehicleOwner.driver            (VehicleDriver, no vehicle selected)
//
// All in-SCC edges (vehicle, owner, driver) are forced nullable by the SCC
// rule regardless of their schema nullability.

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  // ── layer 1: vehicle is selected ────────────────────────────────────────────

  group('layer 1 — VehicleDriver.vehicle', () {
    test('getVehicleDriver returns the driver id and name', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      expect(res.getVehicleDriver.id, equals('vd-1'));
      expect(res.getVehicleDriver.name, equals('Alex Driver'));
    });

    test('vehicle is not null (selected at layer 1)', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      expect(res.getVehicleDriver.vehicle, isNotNull);
    });

    test('Car variant: model is accessible', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      final vehicle = res.getVehicleDriver.vehicle;
      expect(vehicle, isA<Car>());
      expect((vehicle as Car).model, equals('Tesla Model 3'));
    });

    test('Bike variant: brand is accessible', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-2');
      final vehicle = res.getVehicleDriver.vehicle;
      expect(vehicle, isA<Bike>());
      expect((vehicle as Bike).brand, equals('Trek FX3'));
    });
  });

  // ── layer 2: owner is selected ───────────────────────────────────────────────

  group('layer 2 — Vehicle.owner', () {
    test('Car.owner is not null (selected at layer 2)', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      expect(res.getVehicleDriver.vehicle?.owner, isNotNull);
    });

    test('Car.owner has correct id and name', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      final owner = res.getVehicleDriver.vehicle?.owner;
      expect(owner?.id, equals('vo-1'));
      expect(owner?.name, equals('Alice Owner'));
    });

    test('Bike.owner has correct id and name', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-2');
      final owner = res.getVehicleDriver.vehicle?.owner;
      expect(owner?.id, equals('vo-2'));
      expect(owner?.name, equals('Bob Owner'));
    });
  });

  // ── layer 3: driver is selected ──────────────────────────────────────────────

  group('layer 3 — VehicleOwner.driver', () {
    test('owner.driver is not null (selected at layer 3)', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      expect(res.getVehicleDriver.vehicle?.owner?.driver, isNotNull);
    });

    test('owner.driver has correct id and name', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      final driver = res.getVehicleDriver.vehicle?.owner?.driver;
      expect(driver?.id, equals('vd-1'));
      expect(driver?.name, equals('Alex Driver'));
    });
  });

  // ── layer 4: cycle truncated — vehicle is null ───────────────────────────────

  group('layer 4 — cycle truncated at depth 3', () {
    test('owner.driver.vehicle is null (not selected beyond depth 3)', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-1');
      expect(res.getVehicleDriver.vehicle?.owner?.driver?.vehicle, isNull);
    });

    test('owner.driver.vehicle is null for Bike variant too', () async {
      final res = await client.queries.getVehicleDriver(id: 'vd-2');
      expect(res.getVehicleDriver.vehicle?.owner?.driver?.vehicle, isNull);
    });
  });
}
