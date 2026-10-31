import Foundation
import XCTest
@testable import GraphLinkGenerated

final class LiteralArgumentsTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    private func sentQuery() throws -> String {
        let data = Data(adapter.getLastCall()!.rawPayload.utf8)
        let payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return payload["query"] as! String
    }

    func test_stringLiteral_isSentInline_andNeedsNoParameter() async throws {
        adapter.registerData("findFirstUser", n(("findUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.findFirstUser()
        XCTAssertEqual(res.findUser?.name, "Alice Smith")
        XCTAssertTrue(adapter.getLastCall()!.variables.isEmpty)
        XCTAssertTrue(try sentQuery().contains("findUser(id: \"user-1\")"))
    }

    func test_enumLiteral_isSentInline() async throws {
        adapter.registerData("listActiveUsers", n(("listUsersByStatus", [Fixtures.kUserAliceJson])))
        let res = try await client.queries.listActiveUsers()
        XCTAssertEqual(res.listUsersByStatus.count, 1)
        XCTAssertTrue(adapter.getLastCall()!.variables.isEmpty)
        XCTAssertTrue(try sentQuery().contains("listUsersByStatus(status: ACTIVE)"))
    }

    func test_severalLiterals_inOneField_areSentInline() async throws {
        adapter.registerData("searchAlice", n(("searchUsers", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.searchAlice()
        XCTAssertTrue(adapter.getLastCall()!.variables.isEmpty)
        XCTAssertTrue(try sentQuery().contains("searchUsers(name: \"Alice\",limit: 5)"))
    }

    func test_literalAndVariable_canBeMixed() async throws {
        adapter.registerData("searchWithFixedLimit", n(("searchUsers", [Fixtures.kUserBobJson])))
        _ = try await client.queries.searchWithFixedLimit(name: "Bob")
        XCTAssertEqual(adapter.getLastCall()!.variables["name"] as? String, "Bob")
        XCTAssertTrue(try sentQuery().contains("searchUsers(name: $name,limit: 10)"))
    }

    func test_dollarSigns_insideALiteral_reachTheServerUnchanged() async throws {
        adapter.registerData("searchPrice", n(("searchUsers", [Any]())))
        _ = try await client.queries.searchPrice()
        XCTAssertTrue(adapter.getLastCall()!.variables.isEmpty)
        XCTAssertTrue(try sentQuery().contains("name: \"cost $5 or $6\""))
    }
}
