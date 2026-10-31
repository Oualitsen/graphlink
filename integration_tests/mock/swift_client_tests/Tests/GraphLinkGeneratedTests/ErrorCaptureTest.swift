import XCTest
@testable import GraphLinkGenerated

private let kAddress = AddressInput(street: "1 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice", email: "alice@test.com",
    status: .active, address: kAddress
)

// ── getUserOrErrors — success ───────────────────────────────────────────────

final class ErrorCaptureTest_GetUserOrErrorsSuccess: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("getUserOrErrors", n(("getUserOrErrors", Fixtures.kUserAliceJson)))
    }

    func test_returnsFullResponse() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res)
    }

    func test_data_isNotNull() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.data)
    }

    func test_data_user_hasCorrectId() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertEqual(res.data!.getUserOrErrors.id, "user-1")
    }

    func test_errors_isNullOrEmpty_onSuccess() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertTrue(res.errors == nil || res.errors!.isEmpty)
    }

    func test_doesNotThrow_onSuccess() async throws {
        _ = try await client.queries.getUserOrErrors(id: "user-1")
    }
}

// ── getUserOrErrors — partial success (data + errors) ──────────────────────

final class ErrorCaptureTest_GetUserOrErrorsWithErrors: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerDataAndErrors(
            "getUserOrErrors",
            n(("getUserOrErrors", Fixtures.kUserAliceJson)),
            [Fixtures.kGraphQLError]
        )
    }

    func test_doesNotThrow_whenErrorsPresent() async throws {
        _ = try await client.queries.getUserOrErrors(id: "user-1")
    }

    func test_data_isStillPresent_whenErrorsPresent() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.data)
        XCTAssertNotNil(res.data!.getUserOrErrors)
    }

    func test_errors_isNonEmpty() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.errors)
        XCTAssertFalse(res.errors!.isEmpty)
    }

    func test_errors_firstMessage_isCorrect() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertEqual(res.errors![0].message, "Not found")
    }
}

// ── getUserOrErrors — full error (data: null) ───────────────────────────────

final class ErrorCaptureTest_GetUserOrErrorsNullData: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerErrors("getUserOrErrors", [Fixtures.kGraphQLError])
    }

    func test_doesNotThrow_whenDataNull() async throws {
        _ = try await client.queries.getUserOrErrors(id: "user-1")
    }

    func test_data_isNull() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNil(res.data)
    }

    func test_errors_isNonEmpty() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.errors)
        XCTAssertFalse(res.errors!.isEmpty)
    }
}

// ── findUserOrErrors — nullable return ──────────────────────────────────────

final class ErrorCaptureTest_FindUserOrErrorsWithErrors: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerErrors("findUserOrErrors", [Fixtures.kGraphQLError])
    }

    func test_doesNotThrow() async throws {
        _ = try await client.queries.findUserOrErrors(id: "user-1")
    }

    func test_data_fieldIsNull() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-1")
        XCTAssertTrue(res.data == nil || res.data!.findUserOrErrors == nil)
    }

    func test_errors_isNonEmpty() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.errors)
        XCTAssertFalse(res.errors!.isEmpty)
    }

    func test_errors_message_isCorrect() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-1")
        XCTAssertEqual(res.errors![0].message, "Not found")
    }
}

// ── findUserOrErrors — success ──────────────────────────────────────────────

final class ErrorCaptureTest_FindUserOrErrorsSuccess: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_data_isPresent_whenNoErrors() async throws {
        adapter.registerData("findUserOrErrors", n(("findUserOrErrors", Fixtures.kUserAliceJson)))
        let res = try await client.queries.findUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.data)
        XCTAssertNotNil(res.data!.findUserOrErrors)
        XCTAssertEqual(res.data!.findUserOrErrors!.id, "user-1")
    }
}

// ── Non-captureErrors query throws on errors ────────────────────────────────

final class ErrorCaptureTest_NonCaptureErrorsThrows: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_getUser_throws_whenResponseHasErrors() async throws {
        adapter.registerDataAndErrors(
            "getUser",
            n(("getUser", Fixtures.kUserAliceJson)),
            [Fixtures.kGraphQLError]
        )
        do {
            _ = try await client.queries.getUser(id: "user-1")
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}

// ── createUserOrErrors mutation ─────────────────────────────────────────────

final class ErrorCaptureTest_CreateUserOrErrorsMutation: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_doesNotThrow_whenErrorsPresent() async throws {
        adapter.registerDataAndErrors(
            "createUserOrErrors",
            n(("createUserOrErrors", Fixtures.kUserAliceJson)),
            [Fixtures.kGraphQLError]
        )
        _ = try await client.mutations.createUserOrErrors(input: kCreateInput)
    }

    func test_data_isPresent_alongside_errors() async throws {
        adapter.registerDataAndErrors(
            "createUserOrErrors",
            n(("createUserOrErrors", Fixtures.kUserAliceJson)),
            [Fixtures.kGraphQLError]
        )
        let res = try await client.mutations.createUserOrErrors(input: kCreateInput)
        XCTAssertNotNil(res.data)
        XCTAssertNotNil(res.data!.createUserOrErrors)
    }

    func test_errors_arePopulated() async throws {
        adapter.registerDataAndErrors(
            "createUserOrErrors",
            n(("createUserOrErrors", Fixtures.kUserAliceJson)),
            [Fixtures.kGraphQLError]
        )
        let res = try await client.mutations.createUserOrErrors(input: kCreateInput)
        XCTAssertFalse(res.errors!.isEmpty)
    }

    func test_success_noErrors_dataIsPresent() async throws {
        adapter.registerData("createUserOrErrors", n(("createUserOrErrors", Fixtures.kUserAliceJson)))
        let res = try await client.mutations.createUserOrErrors(input: kCreateInput)
        XCTAssertNotNil(res.data!.createUserOrErrors)
        XCTAssertTrue(res.errors == nil || res.errors!.isEmpty)
    }
}
