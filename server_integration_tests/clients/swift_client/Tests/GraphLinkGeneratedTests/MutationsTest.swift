import XCTest
@testable import GraphLinkGenerated

final class MutationsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testCreateArticle_returnsCreatedArticleWithGivenInput() async throws {
        let res = try await client.mutations.createArticle(
            input: CreateArticleInput(title: "New Post", authorId: "2"),
            fieldArgs: CreateArticleFieldArgs(latestArticlesLimit: 2)
        )
        XCTAssertEqual(res.createArticle.title, "New Post")
        XCTAssertEqual(res.createArticle.authorId, "2")
        XCTAssertFalse(res.createArticle.id.isEmpty)
    }

    func testUpdateArticle_updatesTitleAndReturnsArticle() async throws {
        let created = try await client.mutations.createArticle(
            input: CreateArticleInput(title: "Original Title", authorId: "1"),
            fieldArgs: CreateArticleFieldArgs(latestArticlesLimit: 2)
        )
        let res = try await client.mutations.updateArticle(
            input: UpdateArticleInput(id: created.createArticle.id, title: "Updated Title"),
            fieldArgs: UpdateArticleFieldArgs(latestArticlesLimit: 2)
        )
        XCTAssertEqual(res.updateArticle.id, created.createArticle.id)
        XCTAssertEqual(res.updateArticle.title, "Updated Title")
    }

    func testDeleteArticle_returnsTrueWhenArticleExists() async throws {
        let created = try await client.mutations.createArticle(
            input: CreateArticleInput(title: "To Delete", authorId: "1"),
            fieldArgs: CreateArticleFieldArgs(latestArticlesLimit: 2)
        )
        let res = try await client.mutations.deleteArticle(id: created.createArticle.id)
        XCTAssertTrue(res.deleteArticle)
    }

    func testDeleteArticle_returnsFalseWhenArticleDoesNotExist() async throws {
        let res = try await client.mutations.deleteArticle(id: "missing-id")
        XCTAssertFalse(res.deleteArticle)
    }

    func testAckPriority_enumMutationArgumentDeserializesReturnsConstantAck() async throws {
        let res = try await client.mutations.ackPriority(level: Priority.high)
        XCTAssertEqual(res.ackPriority, "OK")
    }
}
