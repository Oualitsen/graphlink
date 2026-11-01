import XCTest
@testable import GraphLinkGenerated

final class GlHashTest: XCTestCase {
    private let client = Helpers.newClient(ApqServer())

    func testHashesAQueryLikeAReferenceSha256() {
        XCTAssertEqual(client.queries.glHash("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(client.queries.glHash(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testHashesARealGraphQLDocument() {
        XCTAssertEqual(
            client.queries.glHash("query GetUser($id: ID!){getUser(id:$id){id name}}"),
            "76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc"
        )
    }

    func testIsTheSameForRepeatedCalls() {
        let first = client.queries.glHash("query A{a}")
        XCTAssertEqual(client.queries.glHash("query A{a}"), first)
        XCTAssertNotEqual(client.queries.glHash("query B{b}"), first)
    }

    func testIsSharedByQueriesAndMutationsThroughTheBaseClass() {
        XCTAssertEqual(client.mutations.glHash("abc"), client.queries.glHash("abc"))
    }
}
