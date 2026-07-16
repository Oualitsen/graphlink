import XCTest
@testable import GraphLinkGenerated

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")

// ── CreateUserInput — required fields ───────────────────────────────────────

final class InputsTest_CreateUserInput_RequiredFields: XCTestCase {
    var client: GraphLinkClient!

    private let minimalInput = CreateUserInput(
        name: "Alice Smith",
        email: "alice@test.com",
        status: .active,
        address: AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
    )

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_createUser_response_deserializesCorrectly() async throws {
        let res = try await client.mutations.createUser(input: minimalInput)
        XCTAssertNotNil(res.createUser)
        XCTAssertEqual(res.createUser.name, "Alice Smith")
    }

    func test_createUser_address_isReflectedInResponse() async throws {
        let res = try await client.mutations.createUser(input: minimalInput)
        XCTAssertNotNil(res.createUser.address)
        XCTAssertEqual(res.createUser.address.city, "Springfield")
    }

    func test_createUser_status_isReflectedInResponse() async throws {
        let res = try await client.mutations.createUser(input: minimalInput)
        XCTAssertEqual(res.createUser.status, UserStatus.active)
    }
}

// ── CreateUserInput — optional fields ───────────────────────────────────────

final class InputsTest_CreateUserInput_OptionalFields: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_createUser_withPriority_isReflectedInResponse() async throws {
        let input = CreateUserInput(
            name: "Alice Smith", email: "alice@test.com",
            status: .active, priority: .high,
            address: kAddressInput
        )
        let res = try await client.mutations.createUser(input: input)
        XCTAssertEqual(res.createUser.priority, Priority.high)
    }
}

// ── UpdateUserInput — all nullable fields ───────────────────────────────────

final class InputsTest_UpdateUserInput_AllNullable: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_updateUser_response_deserializesCorrectly() async throws {
        let input = UpdateUserInput(name: "Alice Updated")
        let res = try await client.mutations.updateUser(id: "user-1", input: input)
        XCTAssertNotNil(res.updateUser)
        XCTAssertEqual(res.updateUser.name, "Alice Updated")
    }

    func test_updateUser_statusNotInInput_preservesOriginalStatus() async throws {
        let input = UpdateUserInput(name: "Alice Updated")
        let res = try await client.mutations.updateUser(id: "user-1", input: input)
        XCTAssertEqual(res.updateUser.status, UserStatus.active)
    }
}

// ── AddressInput — nullable zip (pure unit tests, no server needed) ────────

final class InputsTest_AddressInput_NullableZip: XCTestCase {
    func test_addressInput_zip_isNull_whenNotSet() {
        let addr = AddressInput(street: "1 Road", city: "Town", country: "US")
        XCTAssertNil(addr.zip)
    }

    func test_addressInput_zip_isPresent_whenSet() {
        let addr = AddressInput(street: "1 Road", city: "Town", country: "US", zip: "00001")
        XCTAssertEqual(addr.zip, "00001")
    }
}
