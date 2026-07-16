import Foundation
import XCTest
@testable import GraphLinkGenerated

// ── listUsersWithDefaults — operation argument defaults ──────────────────

final class DefaultValuesTest_ListUsersWithDefaults: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testReturnsUsers_withoutArguments() async throws {
        let res = try await client.queries.listUsersWithDefaults()
        XCTAssertNotNil(res.listUsersWithDefaults)
        XCTAssertTrue(!res.listUsersWithDefaults.isEmpty)
    }

    func testExplicitLimit_overridesDefault() async throws {
        let res = try await client.queries.listUsersWithDefaults(limit: 1)
        XCTAssertEqual(res.listUsersWithDefaults.count, 1)
    }

    func testExplicitRole_canBeProvided() async throws {
        let res = try await client.queries.listUsersWithDefaults(role: Role.admin)
        XCTAssertTrue(!res.listUsersWithDefaults.isEmpty)
    }
}

// ── createWithDefaults — input field defaults ────────────────────────────

final class DefaultValuesTest_CreateWithDefaults: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testRole_defaultsToUSER() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.role, Role.user)
    }

    func testAge_defaultsTo18() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.age, 18)
    }

    func testIsActive_defaultsToTrue() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertTrue(res.createWithDefaults.isActive)
    }

    func testScore_defaultsToFourPointFive() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.score, 4.5)
    }

    func testNickname_defaultsToAnonymous() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.nickname, "anonymous")
    }

    func testTags_defaultsToDartAndGraphql() async throws {
        let input = CreateWithDefaultsInput(name: "test")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.tags, ["dart", "graphql"])
    }

    func testName_isEchoed() async throws {
        let input = CreateWithDefaultsInput(name: "explicit-name")
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.name, "explicit-name")
    }

    func testExplicitValues_overrideDefaults() async throws {
        let input = CreateWithDefaultsInput(
            name: "override-test",
            role: Role.admin,
            age: 99,
            isActive: false,
            score: 9.9,
            nickname: "custom",
            tags: ["custom-tag"]
        )
        let res = try await client.mutations.createWithDefaults(input: input)
        XCTAssertEqual(res.createWithDefaults.name, "override-test")
        XCTAssertEqual(res.createWithDefaults.role, Role.admin)
        XCTAssertEqual(res.createWithDefaults.age, 99)
        XCTAssertFalse(res.createWithDefaults.isActive)
        XCTAssertEqual(res.createWithDefaults.score, 9.9)
        XCTAssertEqual(res.createWithDefaults.nickname, "custom")
        XCTAssertEqual(res.createWithDefaults.tags, ["custom-tag"])
    }
}

// ── createWithNestedDefaults — nested object/list defaults ───────────────

final class DefaultValuesTest_CreateWithNestedDefaults: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testName_isEchoed() async throws {
        let input = NestedDefaultsInput(name: "nested-test")
        let res = try await client.mutations.createWithNestedDefaults(input: input)
        XCTAssertEqual(res.createWithNestedDefaults.name, "nested-test")
    }

    // ── Object default ──────────────────────────────────────────────────

    func testAddress_defaultsToFullObject() async throws {
        let input = NestedDefaultsInput(name: "obj-default")
        let res = try await client.mutations.createWithNestedDefaults(input: input)
        XCTAssertNotNil(res.createWithNestedDefaults.address)
        XCTAssertEqual(res.createWithNestedDefaults.address!.street, "123 Main St")
        XCTAssertEqual(res.createWithNestedDefaults.address!.city, "Springfield")
        XCTAssertEqual(res.createWithNestedDefaults.address!.country, "US")
        XCTAssertEqual(res.createWithNestedDefaults.address!.zip, "12345")
    }

    // ── List-of-objects default ─────────────────────────────────────────

    func testContacts_defaultsToListOfTwo() async throws {
        let input = NestedDefaultsInput(name: "list-default")
        let res = try await client.mutations.createWithNestedDefaults(input: input)
        XCTAssertNotNil(res.createWithNestedDefaults.contacts)
        XCTAssertEqual(res.createWithNestedDefaults.contacts!.count, 2)
        XCTAssertEqual(res.createWithNestedDefaults.contacts![0]!.street, "456 Oak Ave")
        XCTAssertEqual(res.createWithNestedDefaults.contacts![0]!.city, "Shelbyville")
        XCTAssertNil(res.createWithNestedDefaults.contacts![0]!.zip)
        XCTAssertEqual(res.createWithNestedDefaults.contacts![1]!.street, "789 Pine Rd")
        XCTAssertEqual(res.createWithNestedDefaults.contacts![1]!.city, "Capital City")
        XCTAssertEqual(res.createWithNestedDefaults.contacts![1]!.zip, "99999")
    }

    // ── List-of-list-of-objects default ─────────────────────────────────

    func testMatrix_defaultsToNestedList() async throws {
        let input = NestedDefaultsInput(name: "matrix-default")
        let res = try await client.mutations.createWithNestedDefaults(input: input)
        XCTAssertNotNil(res.createWithNestedDefaults.matrix)
        XCTAssertEqual(res.createWithNestedDefaults.matrix!.count, 2)
        // Row 0: single address
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]!.count, 1)
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]![0]!.street, "1st St")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]![0]!.city, "Paris")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]![0]!.country, "FR")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]![0]!.zip, "75000")
        // Row 1: single address
        XCTAssertEqual(res.createWithNestedDefaults.matrix![1]!.count, 1)
        XCTAssertEqual(res.createWithNestedDefaults.matrix![1]![0]!.street, "2nd St")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![1]![0]!.city, "Lyon")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![1]![0]!.country, "FR")
        XCTAssertEqual(res.createWithNestedDefaults.matrix![1]![0]!.zip, "69000")
    }

    // ── Explicit values override defaults ───────────────────────────────

    func testExplicitValues_overrideNestedDefaults() async throws {
        let input = NestedDefaultsInput(
            name: "override-nested",
            address: AddressInput(street: "Custom St", city: "Custom City", country: "XX", zip: nil),
            contacts: [AddressInput(street: "One", city: "Two", country: "Three", zip: "44444")],
            matrix: [[AddressInput(street: "A", city: "B", country: "C", zip: nil)]]
        )
        let res = try await client.mutations.createWithNestedDefaults(input: input)
        XCTAssertNotNil(res.createWithNestedDefaults.address)
        XCTAssertEqual(res.createWithNestedDefaults.address!.street, "Custom St")
        XCTAssertEqual(res.createWithNestedDefaults.address!.city, "Custom City")
        XCTAssertEqual(res.createWithNestedDefaults.address!.country, "XX")
        XCTAssertNil(res.createWithNestedDefaults.address!.zip)

        XCTAssertEqual(res.createWithNestedDefaults.contacts!.count, 1)
        XCTAssertEqual(res.createWithNestedDefaults.contacts![0]!.street, "One")

        XCTAssertEqual(res.createWithNestedDefaults.matrix!.count, 1)
        XCTAssertEqual(res.createWithNestedDefaults.matrix![0]![0]!.street, "A")
    }
}

// ── getDriver — field-argument defaults ──────────────────────────────────

final class DefaultValuesTest_GetDriver: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testOdometerKm_isRequired_andEchoedBack() async throws {
        let res = try await client.queries.getDriver(id: "driver-1", fieldArgs: GetDriverFieldArgs(lastUsedMillageOdometerKm: 100))
        XCTAssertEqual(res.getDriver.lastUsedMillage, 100)
    }

    func testLiters_defaultsTo4_whenNotProvided() async throws {
        let res = try await client.queries.getDriver(id: "driver-1", fieldArgs: GetDriverFieldArgs(lastUsedMillageOdometerKm: 200))
        XCTAssertEqual(res.getDriver.lastUsedFuel, 4)
    }

    func testExplicitLiters_overridesDefault() async throws {
        let res = try await client.queries.getDriver(id: "driver-1", fieldArgs: GetDriverFieldArgs(lastUsedMillageOdometerKm: 300, lastUsedFuelLiters: 10))
        XCTAssertEqual(res.getDriver.lastUsedFuel, 10)
    }

    func testBothValues_echoedBack_withExplicitLiters() async throws {
        let res = try await client.queries.getDriver(id: "driver-1", fieldArgs: GetDriverFieldArgs(lastUsedMillageOdometerKm: 500, lastUsedFuelLiters: 25))
        XCTAssertEqual(res.getDriver.lastUsedMillage, 500)
        XCTAssertEqual(res.getDriver.lastUsedFuel, 25)
    }
}
