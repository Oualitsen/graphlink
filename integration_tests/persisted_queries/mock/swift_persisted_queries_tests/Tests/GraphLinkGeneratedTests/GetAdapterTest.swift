import XCTest
@testable import GraphLinkGenerated

final class GetAdapterTest: XCTestCase {
    var server: ApqServer!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        server = ApqServer()
        client = Helpers.newClient(server)
        server.respondTo("persistedLongQuery", ["getUser": Fixtures.kUserAliceJson])
        server.respondTo("persistedShortQuery", ["listUsers": [Any?]()])
        server.respondTo("persistedLongMutation", ["createUser": Fixtures.kUserAliceJson])
    }

    func testLongQuery_asksWithAGetFirstAndRegistersWithAPost() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(server.methods, ["GET", "POST"])
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
        XCTAssertTrue(server.requests[1].keys.contains("query"))
    }

    func testLongQuery_isASingleGetOnceTheServerKnowsIt() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.clearRequests()

        _ = try await client.queries.persistedLongQuery(id: "user-2")

        XCTAssertEqual(server.methods, ["GET"])
    }

    func testGetAdapter_receivesTheHashOnlyPayloadWithNoQuery() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(Set(server.requests[0].keys), ["extensions", "operationName", "variables"])
    }

    func testShortQuery_isAPlainPost() async throws {
        _ = try await client.queries.persistedShortQuery()

        XCTAssertEqual(server.methods, ["POST"])
    }

    func testMutation_sendsItsHashOverPost() async throws {
        _ = try await client.mutations.persistedLongMutation(input: Helpers.createUserInput)

        XCTAssertEqual(server.methods, ["POST", "POST"])
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
    }

    func testServerRefusingGet_getsTheSameHashOnlyRequestAsAPost() async throws {
        server.getSupported = false

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        XCTAssertEqual(server.methods, ["GET", "POST", "POST"])
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.isHashOnly(server.requests[0]))
        XCTAssertTrue(server.requests[1].keys.contains("query"))
    }

    func testServerThatRefusedGet_isNotAskedWithAGetAgain() async throws {
        server.getSupported = false
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        server.clearRequests()

        _ = try await client.queries.persistedLongQuery(id: "user-2")

        XCTAssertEqual(server.methods, ["POST"])
    }

    func testServerWithoutApq_answersTheGetWithARefusalThenGetsTheFullQueryByPost() async throws {
        server.supported = false

        _ = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(server.methods, ["GET", "POST"])
        XCTAssertTrue(server.requests[1].keys.contains("query"))
        XCTAssertFalse(server.requests[1].keys.contains("extensions"))
    }

    func testOtherGetFailures_propagateUntouchedWithNoPost() async throws {
        struct NetworkDown: Error {}
        server.getFailWith = NetworkDown()

        do {
            _ = try await client.queries.persistedLongQuery(id: "user-1")
            XCTFail("expected NetworkDown")
        } catch is NetworkDown {}
        XCTAssertEqual(server.methods, ["GET"])
    }
}
