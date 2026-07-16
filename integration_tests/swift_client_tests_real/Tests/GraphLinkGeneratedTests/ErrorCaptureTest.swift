import Foundation
import XCTest
@testable import GraphLinkGenerated

private let kAddress = AddressInput(street: "1 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice", email: "alice@test.com",
    status: UserStatus.active, address: kAddress
)
private let kErrorInput = CreateUserInput(
    name: "error-user", email: "e@test.com",
    status: UserStatus.active, address: kAddress
)

// ── getUserOrErrors — success ──────────────────────────────────────────────

final class ErrorCaptureTest_GetUserOrErrorsSuccess: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testReturnsFullResponse() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res)
    }

    func testData_isNotNull() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.data)
    }

    func testData_user_hasCorrectId() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertEqual(res.data!.getUserOrErrors.id, "user-1")
    }

    func testErrors_isNullOrEmpty_onSuccess() async throws {
        let res = try await client.queries.getUserOrErrors(id: "user-1")
        XCTAssertTrue(res.errors == nil || res.errors!.isEmpty)
    }

    func testDoesNotThrow_onSuccess() async throws {
        _ = try await client.queries.getUserOrErrors(id: "user-1")
    }
}

// ── getUserOrErrors — server-side error (unknown id) ──────────────────────

final class ErrorCaptureTest_GetUserOrErrorsWithErrors: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testDoesNotThrow_whenServerReturnsError() async throws {
        _ = try await client.queries.getUserOrErrors(id: "unknown-id")
    }

    func testErrors_isNonEmpty_forUnknownId() async throws {
        let res = try await client.queries.getUserOrErrors(id: "unknown-id")
        XCTAssertNotNil(res.errors)
        XCTAssertTrue(!res.errors!.isEmpty)
    }

    func testErrors_hasMessage_forUnknownId() async throws {
        let res = try await client.queries.getUserOrErrors(id: "unknown-id")
        let msg = res.errors![0].message
        XCTAssertTrue(!msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// ── findUserOrErrors — null return (no error) ─────────────────────────────

final class ErrorCaptureTest_FindUserOrErrorsNullReturn: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testDoesNotThrow_forUnknownId() async throws {
        _ = try await client.queries.findUserOrErrors(id: "user-99")
    }

    func testData_fieldIsNull_forUnknownId() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-99")
        XCTAssertTrue(res.data == nil || res.data!.findUserOrErrors == nil)
    }

    func testErrors_isNullOrEmpty_forUnknownId() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-99")
        XCTAssertTrue(res.errors == nil || res.errors!.isEmpty)
    }
}

// ── findUserOrErrors — server error ───────────────────────────────────────

final class ErrorCaptureTest_FindUserOrErrorsWithErrors: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testDoesNotThrow_forErrorId() async throws {
        _ = try await client.queries.findUserOrErrors(id: "error-id")
    }

    func testErrors_isNonEmpty_forErrorId() async throws {
        let res = try await client.queries.findUserOrErrors(id: "error-id")
        XCTAssertNotNil(res.errors)
        XCTAssertTrue(!res.errors!.isEmpty)
    }
}

// ── findUserOrErrors — success ────────────────────────────────────────────

final class ErrorCaptureTest_FindUserOrErrorsSuccess: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testData_isPresent_forKnownId() async throws {
        let res = try await client.queries.findUserOrErrors(id: "user-1")
        XCTAssertNotNil(res.data)
        XCTAssertNotNil(res.data!.findUserOrErrors)
        XCTAssertEqual(res.data!.findUserOrErrors!.id, "user-1")
    }
}

// ── Non-captureErrors query throws on server error ────────────────────────

final class ErrorCaptureTest_NonCaptureErrorsThrows: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testGetUser_throws_forUnknownId() async throws {
        do {
            _ = try await client.queries.getUser(id: "unknown-id")
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}

// ── createUserOrErrors mutation ───────────────────────────────────────────

final class ErrorCaptureTest_CreateUserOrErrorsMutation: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testSuccess_dataIsPresent() async throws {
        let res = try await client.mutations.createUserOrErrors(input: kCreateInput)
        XCTAssertNotNil(res.data)
        XCTAssertNotNil(res.data!.createUserOrErrors)
    }

    func testSuccess_noErrors() async throws {
        let res = try await client.mutations.createUserOrErrors(input: kCreateInput)
        XCTAssertTrue(res.errors == nil || res.errors!.isEmpty)
    }

    func testDoesNotThrow_whenServerReturnsError() async throws {
        _ = try await client.mutations.createUserOrErrors(input: kErrorInput)
    }

    func testErrors_arePopulated_whenServerReturnsError() async throws {
        let res = try await client.mutations.createUserOrErrors(input: kErrorInput)
        XCTAssertNotNil(res.errors)
        XCTAssertTrue(!res.errors!.isEmpty)
    }
}
