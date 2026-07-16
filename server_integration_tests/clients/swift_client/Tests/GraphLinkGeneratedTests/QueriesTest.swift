import XCTest
@testable import GraphLinkGenerated

final class QueriesTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testGetAuthor_returnsAuthorById() async throws {
        let res = try await client.queries.getAuthor(id: "1", fieldArgs: GetAuthorFieldArgs(latestArticlesLimit: 10))
        XCTAssertNotNil(res.getAuthor)
        XCTAssertEqual(res.getAuthor!.id, "1")
        XCTAssertEqual(res.getAuthor!.name, "Ramdane")
    }

    func testGetAuthor_returnsNullForUnknownId() async throws {
        let res = try await client.queries.getAuthor(id: "missing", fieldArgs: GetAuthorFieldArgs(latestArticlesLimit: 10))
        XCTAssertNil(res.getAuthor)
    }

    func testGetAuthor_articlesResolvedViaBatchDataLoaderMapping() async throws {
        let res = try await client.queries.getAuthor(id: "1", fieldArgs: GetAuthorFieldArgs(latestArticlesLimit: 10))
        let titles = Set(res.getAuthor!.articles!.map { $0.title })
        XCTAssertTrue(titles.isSuperset(of: ["GraphLink Basics", "Advanced GraphLink"]))
    }

    func testGetAuthor_latestArticlesResolvedViaNonBatchMappingWithArguments() async throws {
        let res = try await client.queries.getAuthor(id: "1", fieldArgs: GetAuthorFieldArgs(latestArticlesLimit: 10))
        let titles = Set(res.getAuthor!.latestArticles!.map { $0.title })
        XCTAssertTrue(titles.isSuperset(of: ["GraphLink Basics", "Advanced GraphLink"]))
    }

    func testGetAuthorWithoutArticle_doesNotRequireLimitArgumentWhenArticlesNotProjected() async throws {
        let res = try await client.queries.getAuthorWithoutArticle(id: "1")
        XCTAssertNotNil(res.getAuthor)
        XCTAssertEqual(res.getAuthor!.id, "1")
        XCTAssertEqual(res.getAuthor!.name, "Ramdane")
    }

    func testGetArticle_returnsArticleById() async throws {
        let res = try await client.queries.getArticle(id: "1", fieldArgs: GetArticleFieldArgs(latestArticlesLimit: 2))
        XCTAssertEqual(res.getArticle.id, "1")
        XCTAssertEqual(res.getArticle.title, "GraphLink Basics")
    }

    func testGetArticle_authorResolvedViaNonBatchSchemaMapping() async throws {
        let res = try await client.queries.getArticle(id: "1", fieldArgs: GetArticleFieldArgs(latestArticlesLimit: 2))
        XCTAssertEqual(res.getArticle.author?.id, "1")
        XCTAssertEqual(res.getArticle.author?.name, "Ramdane")
    }

    func testGetAuthorAndArticle_resolvesBothRootFieldsWithOwnArgsPlusSharedFragmentArgument() async throws {
        let res = try await client.queries.getAuthorAndArticle(
            authorId: "1", articleId: "3", fieldArgs: GetAuthorAndArticleFieldArgs(latestArticlesLimit: 1)
        )
        XCTAssertEqual(res.author!.id, "1")
        XCTAssertEqual(res.author!.latestArticles!.count, 1)
        XCTAssertEqual(res.article.id, "3")
        XCTAssertEqual(res.article.title, "Alice's First Post")
    }

    func testListAuthors_listAuthorsReturnsAllAuthors() async throws {
        let res = try await client.queries.listAuthors(fieldArgs: ListAuthorsFieldArgs(latestArticlesLimit: 10))
        let ids = Set(res.listAuthors.map { $0.id })
        XCTAssertTrue(ids.isSuperset(of: ["1", "2"]))
    }

    func testListArticles_listArticlesReturnsAllArticles() async throws {
        let res = try await client.queries.listArticles(fieldArgs: ListArticlesFieldArgs(latestArticlesLimit: 2))
        XCTAssertTrue(res.listArticles.map { $0.id }.contains("1"))
    }
}
