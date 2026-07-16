import XCTest
@testable import GraphLinkGenerated

final class SubscriptionsTest: XCTestCase {

    func testArticleCreated_emitsWhenAnArticleIsCreated() async throws {
        let client = Fixtures.newClient()

        let stream = client.subscriptions.articleCreated(fieldArgs: ArticleCreatedFieldArgs(latestArticlesLimit: 2))
        let eventTask = Task {
            try await firstValue(from: stream, timeoutSeconds: 10)
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let created = try await client.mutations.createArticle(
            input: CreateArticleInput(title: "Subscribed Post", authorId: "1"),
            fieldArgs: CreateArticleFieldArgs(latestArticlesLimit: 2)
        )

        let event = try await eventTask.value
        XCTAssertEqual(event.articleCreated.id, created.createArticle.id)
        XCTAssertEqual(event.articleCreated.title, "Subscribed Post")
    }

    func testArticleUpdated_emitsWhenTheMatchingArticleIsUpdated() async throws {
        let client = Fixtures.newClient()

        let created = try await client.mutations.createArticle(
            input: CreateArticleInput(title: "Will Update", authorId: "2"),
            fieldArgs: CreateArticleFieldArgs(latestArticlesLimit: 2)
        )

        let stream = client.subscriptions.articleUpdated(
            id: created.createArticle.id,
            fieldArgs: ArticleUpdatedFieldArgs(latestArticlesLimit: 2)
        )
        let eventTask = Task {
            try await firstValue(from: stream, timeoutSeconds: 10)
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let updated = try await client.mutations.updateArticle(
            input: UpdateArticleInput(id: created.createArticle.id, title: "Updated via subscription"),
            fieldArgs: UpdateArticleFieldArgs(latestArticlesLimit: 2)
        )

        let event = try await eventTask.value
        XCTAssertEqual(event.articleUpdated.id, updated.updateArticle.id)
        XCTAssertEqual(event.articleUpdated.title, "Updated via subscription")
    }
}
