import XCTest
@testable import GraphLinkGenerated

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice Smith",
    email: "alice@test.com",
    status: .active,
    address: kAddressInput
)

// ── createUser ────────────────────────────────────────────────────────────────

final class MutationsTest_CreateUser: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_response_returnsCreatedUser() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertNotNil(res.createUser)
    }

    func test_response_user_hasName() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.name, "Alice Smith")
    }

    func test_response_user_hasEmail() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.email, "alice@test.com")
    }

    func test_response_user_hasCorrectStatus() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.status, UserStatus.active)
    }

    func test_response_user_hasNestedAddress() async throws {
        let res = try await client.mutations.createUser(input: kCreateInput)
        XCTAssertEqual(res.createUser.address.city, "Springfield")
    }
}

// ── deleteUser ───────────────────────────────────────────────────────────────

final class MutationsTest_DeleteUser: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_response_returnsTrue() async throws {
        let res = try await client.mutations.deleteUser(id: "user-1")
        XCTAssertTrue(res.deleteUser)
    }
}

// ── updateUser ───────────────────────────────────────────────────────────────

final class MutationsTest_UpdateUser: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_response_returnsUpdatedUser() async throws {
        let input = UpdateUserInput(name: "Alice Updated")
        let res = try await client.mutations.updateUser(id: "user-1", input: input)
        XCTAssertNotNil(res.updateUser)
        XCTAssertEqual(res.updateUser.id, "user-1")
    }

    func test_response_user_hasUpdatedName() async throws {
        let input = UpdateUserInput(name: "Alice Updated")
        let res = try await client.mutations.updateUser(id: "user-1", input: input)
        XCTAssertEqual(res.updateUser.name, "Alice Updated")
    }

    func test_response_user_statusUnchanged_whenNotInInput() async throws {
        let input = UpdateUserInput(name: "Alice Updated")
        let res = try await client.mutations.updateUser(id: "user-1", input: input)
        XCTAssertEqual(res.updateUser.status, UserStatus.active)
    }
}

// ── transferPost ─────────────────────────────────────────────────────────────

final class MutationsTest_TransferPost: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_response_returnsPost() async throws {
        let res = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertNotNil(res.transferPost)
        XCTAssertEqual(res.transferPost.id, "post-1")
    }

    func test_response_post_authorIsNewOwner() async throws {
        let res = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertEqual(res.transferPost.author?.id, "user-2")
    }
}

// ── resetAll ─────────────────────────────────────────────────────────────────

final class MutationsTest_ResetAll: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_response_returnsTrue() async throws {
        let res = try await client.mutations.resetAll()
        XCTAssertTrue(res.resetAll)
    }
}
