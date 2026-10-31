import Foundation
import XCTest
@testable import GraphLinkGenerated

final class LiteralArgumentsTest: XCTestCase {

    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_stringLiteral_selectsTheRightUser() async throws {
        let res = try await client.queries.findFirstUser()
        XCTAssertEqual(res.findUser?.name, "Alice Smith")
        XCTAssertEqual(res.findUser?.email, "alice@test.com")
    }

    func test_enumLiteral_filtersOnTheServer() async throws {
        let res = try await client.queries.listActiveUsers()
        XCTAssertEqual(res.listUsersByStatus.map { $0.id }, ["user-1"])
    }

    func test_severalLiterals_inOneField_areApplied() async throws {
        let res = try await client.queries.searchAlice()
        XCTAssertEqual(res.searchUsers.map { $0.name }, ["Alice Smith"])
    }

    func test_inlineLimit_isEnforced_whileTheOtherArgumentStaysAVariable() async throws {
        let res = try await client.queries.searchWithFixedLimit(name: "s")
        XCTAssertEqual(res.searchUsers.count, 1)
    }

    func test_dollarSigns_insideALiteral_formAValidQuery() async throws {
        let res = try await client.queries.searchPrice()
        XCTAssertTrue(res.searchUsers.isEmpty)
    }
}
