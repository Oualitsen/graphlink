import XCTest
@testable import GraphLinkGenerated

final class PersistedQueriesRealTest: XCTestCase {
    private static let port = 9997
    private static let graphql = URL(string: "http://localhost:\(port)/graphql")!

    private let newUser = CreateUserInput(
        name: "Persisted Pat",
        email: "pat@test.com",
        status: .active,
        address: AddressInput(street: "s", city: "c", country: "x")
    )

    private var client: GraphLinkClient!

    private func control(_ method: String, _ path: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://localhost:\(Self.port)/test/apq\(path)")!)
        request.httpMethod = method
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func stats() async throws -> [String: Any] {
        try await control("GET", "")
    }

    private func count(_ stats: [String: Any], _ key: String) -> Int {
        (stats[key] as! NSNumber).intValue
    }

    private func newClient() -> GraphLinkClient {
        GraphLinkClient(
            adapter: DefaultGraphLinkURLSessionAdapter(url: Self.graphql).execute,
            getAdapter: DefaultGraphLinkURLSessionGetAdapter(url: Self.graphql).execute,
            wsAdapter: DefaultGraphLinkWebSocketAdapter(url: URL(string: "ws://localhost:\(Self.port)/graphql")!),
            multipartAdapter: DefaultGraphLinkURLSessionMultipartAdapter(url: Self.graphql).executeMultipart
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        _ = try await control("POST", "/reset")
        client = newClient()
    }

    func testLongQuery_isRegisteredOnTheFirstCall_aGetMissThenAPostWithTheDocument() async throws {
        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "misses"), 1)
        XCTAssertEqual(count(stats, "registrations"), 1)
        XCTAssertEqual(count(stats, "stored"), 1)
        XCTAssertEqual(count(stats, "gets"), 1)
    }

    func testLongQuery_isASingleGetHitOnceRegistered() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "hits"), 1)
        XCTAssertEqual(count(stats, "registrations"), 1)
        XCTAssertEqual(count(stats, "gets"), 2)
    }

    func testFreshClient_reusesWhatTheServerAlreadyStored() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")

        let res = try await newClient().queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "hits"), 1)
        XCTAssertEqual(count(stats, "registrations"), 1)
    }

    func testLongQuery_isRegisteredAgainAfterTheServerEvictsIt() async throws {
        _ = try await client.queries.persistedLongQuery(id: "user-1")
        _ = try await control("POST", "/evict")

        let res = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(res.getUser.name, "Alice Smith")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "registrations"), 2)
        XCTAssertEqual(count(stats, "stored"), 1)
    }

    func testLongQuery_stillWorksWhenTheServerDoesNotSupportPersistedQueries() async throws {
        _ = try await control("POST", "/supported/false")

        let first = try await client.queries.persistedLongQuery(id: "user-1")
        let second = try await client.queries.persistedLongQuery(id: "user-1")

        XCTAssertEqual(first.getUser.name, "Alice Smith")
        XCTAssertEqual(second.getUser.name, "Alice Smith")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "stored"), 0)
        XCTAssertEqual(count(stats, "gets"), 1)
    }

    func testLongMutation_isRegisteredAndSentOverPostNeverGet() async throws {
        let res = try await client.mutations.persistedLongMutation(input: newUser)

        XCTAssertEqual(res.createUser.name, "Persisted Pat")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "registrations"), 1)
        XCTAssertEqual(count(stats, "gets"), 0)
    }

    func testLongMutation_isAHashOnlyPostOnceRegistered() async throws {
        _ = try await client.mutations.persistedLongMutation(input: newUser)

        let res = try await client.mutations.persistedLongMutation(input: newUser)

        XCTAssertEqual(res.createUser.email, "pat@test.com")
        let stats = try await stats()
        XCTAssertEqual(count(stats, "hits"), 1)
        XCTAssertEqual(count(stats, "registrations"), 1)
        XCTAssertEqual(count(stats, "gets"), 0)
    }

    func testShortQuery_doesNotUsePersistedQueries() async throws {
        let res = try await client.queries.persistedShortQuery()

        XCTAssertFalse(res.listUsers.isEmpty)
        let stats = try await stats()
        XCTAssertEqual(count(stats, "hits"), 0)
        XCTAssertEqual(count(stats, "misses"), 0)
        XCTAssertEqual(count(stats, "registrations"), 0)
        XCTAssertEqual(count(stats, "gets"), 0)
    }
}
