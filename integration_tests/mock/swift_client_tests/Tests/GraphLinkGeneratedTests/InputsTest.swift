import XCTest
@testable import GraphLinkGenerated

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")

/// A round-tripped-through-JSON variable is `NSNull`, not Swift `nil` — this
/// treats both as "absent" the way the Kotlin source's `assertNull` does.
private func isJSONNull(_ v: Any?) -> Bool {
    guard let v else { return true }
    return v is NSNull
}

// ── CreateUserInput — required fields ───────────────────────────────────────

final class InputsTest_CreateUserInput_RequiredFields: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    private let minimalInput = CreateUserInput(
        name: "Alice Smith",
        email: "alice@test.com",
        status: .active,
        address: AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
    )

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
    }

    func test_createUser_sendsNameInVariables() async throws {
        _ = try await client.mutations.createUser(input: minimalInput)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["name"] as? String, "Alice Smith")
    }

    func test_createUser_sendsStatusAsString() async throws {
        _ = try await client.mutations.createUser(input: minimalInput)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["status"] as? String, "ACTIVE")
    }

    func test_createUser_sendsAddressNested() async throws {
        _ = try await client.mutations.createUser(input: minimalInput)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        let addrVar = inputVar["address"] as! [String: Any?]
        XCTAssertEqual(addrVar["city"] as? String, "Springfield")
    }

    func test_createUser_nullableFields_areNull_whenNotSet() async throws {
        _ = try await client.mutations.createUser(input: minimalInput)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertTrue(isJSONNull(inputVar["priority"] ?? nil))
        XCTAssertTrue(isJSONNull(inputVar["billingAddress"] ?? nil))
        XCTAssertTrue(isJSONNull(inputVar["tags"] ?? nil))
    }

    func test_createUser_response_deserializesCorrectly() async throws {
        let res = try await client.mutations.createUser(input: minimalInput)
        XCTAssertNotNil(res.createUser)
        XCTAssertEqual(res.createUser.id, "user-1")
    }
}

// ── CreateUserInput — optional fields ───────────────────────────────────────

final class InputsTest_CreateUserInput_OptionalFields: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
    }

    func test_createUser_sendsPriority_whenSet() async throws {
        let input = CreateUserInput(
            name: "Alice Smith", email: "alice@test.com",
            status: .active, priority: .high,
            address: kAddressInput
        )
        _ = try await client.mutations.createUser(input: input)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["priority"] as? String, "HIGH")
    }

    func test_createUser_sendsTags_whenSet() async throws {
        let input = CreateUserInput(
            name: "Alice Smith", email: "alice@test.com",
            status: .active, address: kAddressInput,
            tags: ["admin", "beta"]
        )
        _ = try await client.mutations.createUser(input: input)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["tags"] as? [String], ["admin", "beta"])
    }

    func test_createUser_sendsInitialScore_whenSet() async throws {
        let input = CreateUserInput(
            name: "Alice Smith", email: "alice@test.com",
            status: .active, address: kAddressInput,
            initialScore: 100
        )
        _ = try await client.mutations.createUser(input: input)
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["initialScore"] as? Int, 100)
    }
}

// ── UpdateUserInput — all nullable fields ───────────────────────────────────

final class InputsTest_UpdateUserInput_AllNullable: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("updateUser", n(("updateUser", Fixtures.kUserAliceJson)))
    }

    func test_updateUser_emptyInput_sendsNullFields() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput())
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertTrue(isJSONNull(inputVar["name"] ?? nil))
        XCTAssertTrue(isJSONNull(inputVar["status"] ?? nil))
        XCTAssertTrue(isJSONNull(inputVar["priority"] ?? nil))
    }

    func test_updateUser_sendsIdInVariables() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput())
        XCTAssertEqual(adapter.getLastCall()!.variables["id"] as? String, "user-1")
    }

    func test_updateUser_withStatus_sendsStatusAsString() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(status: .suspended))
        let inputVar = adapter.getLastCall()!.variables["input"] as! [String: Any?]
        XCTAssertEqual(inputVar["status"] as? String, "SUSPENDED")
    }

    func test_updateUser_response_deserializesCorrectly() async throws {
        let res = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(name: "Alice Updated"))
        XCTAssertNotNil(res.updateUser)
    }
}

// ── AddressInput — nullable zip ─────────────────────────────────────────────

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
