import Foundation
import XCTest
@testable import GraphLinkGenerated

// Cycle: VehicleDriver → Vehicle (Car|Bike) → VehicleOwner → VehicleDriver
//
// VehicleDriver is annotated @glExpand(depth: 3) in the schema, so the
// auto-generated query recurses 3 hops into the cycle:
//
//   layer 1 — VehicleDriver.vehicle          (Car or Bike)
//   layer 2 — Car/Bike.owner                 (VehicleOwner)
//   layer 3 — VehicleOwner.driver             (VehicleDriver, no vehicle selected)

// ── layer 1: vehicle is selected ─────────────────────────────────────────

final class GlExpandTest_Layer1Vehicle: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testVehicleDriver_hasCorrectId() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertEqual(res.getVehicleDriver.id, "vd-1")
    }

    func testVehicleDriver_hasCorrectName() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertEqual(res.getVehicleDriver.name, "Alex Driver")
    }

    func testVehicle_isNotNull() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertNotNil(res.getVehicleDriver.vehicle)
    }

    func testVehicle_isCarForVd1() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertTrue(res.getVehicleDriver.vehicle is Car)
    }

    func testCar_hasCorrectModel() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let vehicle = res.getVehicleDriver.vehicle as? Car
        XCTAssertEqual(vehicle?.model, "Tesla Model 3")
    }

    func testVehicle_isBikeForVd2() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-2")
        XCTAssertTrue(res.getVehicleDriver.vehicle is Bike)
    }

    func testBike_hasCorrectBrand() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-2")
        let vehicle = res.getVehicleDriver.vehicle as? Bike
        XCTAssertEqual(vehicle?.brand, "Trek FX3")
    }
}

// ── layer 2: owner is selected ───────────────────────────────────────────

final class GlExpandTest_Layer2Owner: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testCar_owner_isNotNull() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertNotNil(res.getVehicleDriver.vehicle?.owner)
    }

    func testCar_owner_hasCorrectId() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let owner: VehicleOwner? = res.getVehicleDriver.vehicle?.owner
        XCTAssertEqual(owner?.id, "vo-1")
    }

    func testCar_owner_hasCorrectName() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let owner: VehicleOwner? = res.getVehicleDriver.vehicle?.owner
        XCTAssertEqual(owner?.name, "Alice Owner")
    }

    func testBike_owner_hasCorrectId() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-2")
        let owner: VehicleOwner? = res.getVehicleDriver.vehicle?.owner
        XCTAssertEqual(owner?.id, "vo-2")
    }

    func testBike_owner_hasCorrectName() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-2")
        let owner: VehicleOwner? = res.getVehicleDriver.vehicle?.owner
        XCTAssertEqual(owner?.name, "Bob Owner")
    }
}

// ── layer 3: driver is selected ──────────────────────────────────────────

final class GlExpandTest_Layer3Driver: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testOwner_driver_isNotNull() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        XCTAssertNotNil(res.getVehicleDriver.vehicle?.owner?.driver)
    }

    func testOwner_driver_hasCorrectId() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let driver: VehicleDriver? = res.getVehicleDriver.vehicle?.owner?.driver
        XCTAssertEqual(driver?.id, "vd-1")
    }

    func testOwner_driver_hasCorrectName() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let driver: VehicleDriver? = res.getVehicleDriver.vehicle?.owner?.driver
        XCTAssertEqual(driver?.name, "Alex Driver")
    }
}

// ── layer 4: cycle truncated ──────────────────────────────────────────────

final class GlExpandTest_Layer4Truncated: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testOwner_driver_vehicle_isNull_forCar() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-1")
        let inner: VehicleDriver? = res.getVehicleDriver.vehicle?.owner?.driver
        XCTAssertNil(inner?.vehicle)
    }

    func testOwner_driver_vehicle_isNull_forBike() async throws {
        let res = try await client.queries.getVehicleDriver(id: "vd-2")
        let inner: VehicleDriver? = res.getVehicleDriver.vehicle?.owner?.driver
        XCTAssertNil(inner?.vehicle)
    }
}
