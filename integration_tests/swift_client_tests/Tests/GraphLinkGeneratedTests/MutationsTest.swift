import XCTest
@testable import GraphLinkGenerated

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice Smith",
    email: "alice@test.com",
    status: .active,
    address: kAddressInput
)

// ── createUser ───────────────────────────────────────────────────────────────

final class MutationsTest_CreateUser: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
    }

    func test_operationName_isCreateUser() async throws {
        _ = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(adapter.getLastCall()?.operationName, "createUser")
    }

    func test_inputObject_isSentAsVariables() async throws {
        _ = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertNotNil(adapter.getLastCall()?.variables["input"] ?? nil)
    }

    func test_response_returnsCreatedUser() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertNotNil(res.createUser)
        XCTAssertEqual(res.createUser.id, "user-1")
    }

    func test_response_user_hasCorrectStatus() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.status, .active)
    }

    func test_response_user_hasNestedAddress() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.address.city, "Springfield")
    }
}

// ── deleteUser ───────────────────────────────────────────────────────────────

final class MutationsTest_DeleteUser: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("deleteUser", n(("deleteUser", true)))
    }

    func test_operationName_isDeleteUser() async throws {
        _ = try await client.mutations.deleteUser(id: "user-1")
        XCTAssertEqual(adapter.getLastCall()?.operationName, "deleteUser")
    }

    func test_idArgument_isSentInVariables() async throws {
        _ = try await client.mutations.deleteUser(id: "user-1")
        XCTAssertEqual(adapter.getLastCall()?.variables["id"] as? String, "user-1")
    }

    func test_response_returnsTrue() async throws {
        let res = try await client.mutations.deleteUser(id: "user-1")
        XCTAssertTrue(res.deleteUser)
    }
}

// ── updateUser ───────────────────────────────────────────────────────────────

final class MutationsTest_UpdateUser: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("updateUser", n(("updateUser", Fixtures.kUserAliceJson)))
    }

    func test_operationName_isUpdateUser() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(name: "Alice Updated"))
        XCTAssertEqual(adapter.getLastCall()?.operationName, "updateUser")
    }

    func test_idAndInput_areSentInVariables() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(name: "Alice Updated"))
        XCTAssertEqual(adapter.getLastCall()?.variables["id"] as? String, "user-1")
        XCTAssertNotNil(adapter.getLastCall()?.variables["input"] ?? nil)
    }

    func test_response_returnsUpdatedUser() async throws {
        let res = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(status: .inactive))
        XCTAssertNotNil(res.updateUser)
        XCTAssertEqual(res.updateUser.id, "user-1")
    }

    func test_nullableField_inInput_isSentAsNull() async throws {
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput())
        let inputVar = adapter.getLastCall()?.variables["input"] as? [String: Any?]
        XCTAssertNotNil(inputVar)
        XCTAssertNil(inputVar?["status"] ?? nil)
    }
}

// ── transferPost ─────────────────────────────────────────────────────────────

final class MutationsTest_TransferPost: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("transferPost", n(("transferPost", Fixtures.kPostJson)))
    }

    func test_operationName_isTransferPost() async throws {
        _ = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertEqual(adapter.getLastCall()?.operationName, "transferPost")
    }

    func test_bothArgs_areSentInVariables() async throws {
        _ = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertEqual(adapter.getLastCall()?.variables["postId"] as? String, "post-1")
        XCTAssertEqual(adapter.getLastCall()?.variables["newAuthorId"] as? String, "user-2")
    }

    func test_response_returnsPost() async throws {
        let res = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertNotNil(res.transferPost)
        XCTAssertEqual(res.transferPost.id, "post-1")
    }
}

// ── resetAll ─────────────────────────────────────────────────────────────────

final class MutationsTest_ResetAll: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("resetAll", n(("resetAll", true)))
    }

    func test_operationName_isResetAll() async throws {
        _ = try await client.mutations.resetAll()
        XCTAssertEqual(adapter.getLastCall()?.operationName, "resetAll")
    }

    func test_response_returnsTrue() async throws {
        let res = try await client.mutations.resetAll()
        XCTAssertTrue(res.resetAll)
    }
}

// ── Call count sanity ───────────────────────────────────────────────────────

final class MutationsTest_CallCount: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_eachMutationCallIsRecorded() async throws {
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
        adapter.registerData("deleteUser", n(("deleteUser", true)))
        _ = try await client.mutations.createUser(input: kCreateInput)
        _ = try await client.mutations.deleteUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 2)
    }
}
