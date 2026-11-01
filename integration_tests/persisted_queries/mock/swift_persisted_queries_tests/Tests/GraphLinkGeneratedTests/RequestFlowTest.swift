import XCTest
@testable import GraphLinkGenerated

final class RequestFlowTest: XCTestCase {
    var server: ApqServer!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        server = ApqServer()
        client = Helpers.newClient(server)
    }

    private func registerLongQuery() {
        server.respondTo("persistedLongQuery", ["getUser": Fixtures.kUserAliceJson])
    }

    // ── a long query ─────────────────────────────────────────────────────────

    func testLongQuery_isSentAsAHashFirstAndRegisteredByTheRetry() async throws {
        registerLongQuery()

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertFalse(server.requests[0].keys.contains("query"))
        XCTAssertEqual(server.requests[0]["operationName"] as? String, "persistedLongQuery")
        XCTAssertEqual(server.requests[0]["variables"] as? [String: String], ["id": "user-1"])
        XCTAssertTrue(server.requests[1]["query"] is String)
        XCTAssertEqual(server.requests[1]["variables"] as? [String: String], ["id": "user-1"])
    }

    func testLongQuery_hashIsTheSha256OfTheQueryTheRetryCarries() async throws {
        registerLongQuery()

        _ = try await client.queries.persistedLongQuery(id: "user-1")

        let retry = server.requests[1]
        XCTAssertEqual(Helpers.hashOf(retry)["sha256Hash"] as? String, GraphLinkSha256.hex(retry["query"] as! String))
        XCTAssertEqual(Helpers.hashOf(retry)["version"] as? Int, 1)
        XCTAssertEqual(Helpers.hashOf(server.requests[0])["sha256Hash"] as? String, Helpers.hashOf(retry)["sha256Hash"] as? String)
    }

    func testLongQuery_isASingleRequestOnceTheServerKnowsIt() async throws {
        registerLongQuery()
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.clearRequests()

        _ = try await client.queries.persistedLongQuery(id: "user-2")

        XCTAssertEqual(server.requests.count, 1)
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
        XCTAssertEqual(server.requests[0]["variables"] as? [String: String], ["id": "user-2"])
    }

    func testLongQuery_isRegisteredAgainAfterTheServerEvictsIt() async throws {
        registerLongQuery()
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.evict()
        server.clearRequests()

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
        XCTAssertTrue(server.requests[1].keys.contains("query"))
    }

    // ── short query, mutation ────────────────────────────────────────────────

    func testShortQuery_isSentInFullWithNoHash() async throws {
        server.respondTo("persistedShortQuery", ["listUsers": [Any?]()])

        _ = try await client.queries.persistedShortQuery()

        XCTAssertEqual(server.requests.count, 1)
        XCTAssertTrue((server.requests[0]["query"] as! String).contains("listUsers"))
        XCTAssertFalse(server.requests[0].keys.contains("extensions"))
    }

    func testLongMutation_usesTheSameHashThenRegisterFlow() async throws {
        server.respondTo("persistedLongMutation", ["createUser": Fixtures.kUserAliceJson])

        let res = try await client.mutations.persistedLongMutation(input: Helpers.createUserInput)

        XCTAssertEqual(res.createUser.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
        XCTAssertTrue(server.requests[1].keys.contains("query"))
    }

    // ── a server without APQ ─────────────────────────────────────────────────

    func testServerWithoutApq_getsTheFullQueryRightAfterTheFirstRefusal() async throws {
        server.supported = false
        registerLongQuery()

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.requests[1].keys.contains("query"))
        XCTAssertFalse(server.requests[1].keys.contains("extensions"))
    }

    func testServerWithoutApq_isNotAskedAboutHashesAgain() async throws {
        server.supported = false
        registerLongQuery()
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.clearRequests()

        _ = try await client.queries.persistedLongQuery(id: "user-2")

        XCTAssertEqual(server.requests.count, 1)
        XCTAssertTrue(server.requests[0].keys.contains("query"))
        XCTAssertFalse(server.requests[0].keys.contains("extensions"))
    }

    // ── errors ───────────────────────────────────────────────────────────────

    func testServerReportingAMissingHashOnlyByItsCode_stillGetsTheRetry() async throws {
        server.notFoundMessage = "Unknown query"
        registerLongQuery()

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.requests[1].keys.contains("query"))
    }

    func testGraphQLError_isReturnedAsIsWithoutASecondRequest() async throws {
        registerLongQuery()
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.clearRequests()
        server.respondWithErrors("persistedLongQuery", [["message": "boom"]])

        do {
            _ = try await client.queries.persistedLongQuery(id: "user-1")
            XCTFail("expected a GraphLinkException")
        } catch is GraphLinkException {}
        XCTAssertEqual(server.requests.count, 1)
    }

    func testTransportFailure_propagatesWithoutASecondRequest() async throws {
        struct Timeout: Error {}
        server.respondTo("persistedLongMutation", ["createUser": Fixtures.kUserAliceJson])
        server.failWith = Timeout()

        do {
            _ = try await client.mutations.persistedLongMutation(input: Helpers.createUserInput)
            XCTFail("expected Timeout")
        } catch is Timeout {}
        XCTAssertEqual(server.methods, ["POST"])
    }

    func testCachedQuery_hashesTheAssembledRequestNotItsPieces() async throws {
        server.respondTo("fetchCachedPair", ["user": Fixtures.kUserAliceJson, "post": Fixtures.kPostJson])

        let res = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")

        XCTAssertEqual(res.user.name, "Alice Smith")
        XCTAssertEqual(server.requests.count, 2)
        let retry = server.requests[1]
        XCTAssertEqual(Helpers.hashOf(retry)["sha256Hash"] as? String, GraphLinkSha256.hex(retry["query"] as! String))
        XCTAssertTrue((retry["query"] as! String).contains("getCachedUser"))
    }
}
