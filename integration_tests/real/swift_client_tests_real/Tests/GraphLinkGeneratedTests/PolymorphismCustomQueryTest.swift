import Foundation
import XCTest
@testable import GraphLinkGenerated

private func collectEvents<T>(_ stream: AsyncThrowingStream<T, Error>, count: Int, timeout: TimeInterval = 10) async throws -> [T] {
    try await withThrowingTaskGroup(of: [T].self) { group in
        group.addTask {
            var events: [T] = []
            for try await value in stream {
                events.append(value)
                if events.count >= count { break }
            }
            return events
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

final class PolymorphismCustomQueryTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_inlineFragmentsOnEveryMemberOfAUnion() async throws {
        let photo = try await client.queries.fetchAttachment(id: "ph1").attachment
        let video = try await client.queries.fetchAttachment(id: "v1").attachment
        let document = try await client.queries.fetchAttachment(id: "d1").attachment
        XCTAssertEqual((photo as? Photo)?.width, 640)
        XCTAssertEqual((video as? Video)?.seconds, 30)
        XCTAssertEqual((document as? Document)?.pages, 12)
        let missing = try await client.queries.fetchAttachment(id: "nope").attachment
        XCTAssertNil(missing)
    }

    func test_oneFragmentSharedByTwoRootFields() async throws {
        let res = try await client.queries.fetchArticleAndAttachment(articleId: "a1", attachmentId: "v1")
        XCTAssertEqual(res.article.cover?.id, "ph1")
        XCTAssertEqual(res.attachment?.id, "v1")
        XCTAssertEqual((res.attachment as? Video_IdSeconds)?.seconds, 30)
    }

    func test_anInterfaceSelectionWithInlineFragmentsAndASharedFragment() async throws {
        let feed = try await client.queries.fetchFeed().feed
        XCTAssertEqual(feed.count, 4)
        let article = try XCTUnwrap(feed[0] as? Article_AttachmentsCoverCreatedBy_pztuu6)
        XCTAssertEqual(article.title, "Hello")
        XCTAssertEqual((article.cover as? Photo_IdUrl)?.url, "http://cdn/1.png")
        XCTAssertEqual(article.attachments.map { $0.id }, ["ph1", "v1", "d1"])
        XCTAssertEqual((feed[1] as? Comment)?.text, "Nice")
        let second = try XCTUnwrap(feed[2] as? Article_AttachmentsCoverCreatedBy_pztuu6)
        XCTAssertNil(second.cover)
    }

    func test_anInterfaceSelectionThatNamesOnlySomeImplementers() async throws {
        let article = try await client.queries.fetchNode(id: "a1").node
        XCTAssertEqual((article as? Article_CreatedByIdTitle)?.title, "Hello")
        XCTAssertEqual((article as? Article_CreatedByIdTitle)?.createdBy, "alice")
        let comment = try await client.queries.fetchNode(id: "c1").node
        XCTAssertEqual((comment as? Comment_CreatedById)?.createdBy, "bob")
        let missing = try await client.queries.fetchNode(id: "nope").node
        XCTAssertNil(missing)
    }

    func test_twoQueriesSelectDifferentShapesOfTheSameUnion() async throws {
        let photo = try await client.queries.fetchPhotoParts(id: "ph1").attachment
        XCTAssertEqual((photo as? Photo)?.width, 640)
        XCTAssertEqual((photo as? Photo)?.url, "http://cdn/1.png")
        let video = try await client.queries.fetchPhotoParts(id: "v1").attachment
        XCTAssertEqual((video as? Video_Id)?.id, "v1")
        let full = try await client.queries.fetchAttachment(id: "ph1").attachment
        XCTAssertEqual((full as? Photo)?.width, 640)
    }

    func test_aUnionStreamEmitsEachMember() async throws {
        let events = try await collectEvents(client.subscriptions.attachmentAdded(), count: 3)
        XCTAssertTrue(events[0].attachmentAdded is Photo)
        XCTAssertTrue(events[1].attachmentAdded is Video)
        XCTAssertTrue(events[2].attachmentAdded is Document)
    }

    func test_anInterfaceStreamEmitsEachImplementer() async throws {
        let events = try await collectEvents(client.subscriptions.entityPublished(), count: 2)
        XCTAssertTrue(events[0].entityPublished is Article)
        XCTAssertTrue(events[1].entityPublished is Comment)
    }
}
