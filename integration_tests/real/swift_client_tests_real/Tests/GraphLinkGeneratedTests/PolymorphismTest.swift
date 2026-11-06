import Foundation
import XCTest
@testable import GraphLinkGenerated

private func kind(_ value: Any?) -> String {
    switch value {
    case is Photo: return "Photo"
    case is Video: return "Video"
    case is Document: return "Document"
    case is Article: return "Article"
    case is Comment: return "Comment"
    case nil: return "nil"
    default: return "other"
    }
}

private func kinds<T>(_ values: [T?]) -> [String] { values.map { kind($0) } }

private func failure<T>(_ call: () async throws -> T) async -> Error? {
    do {
        _ = try await call()
        return nil
    } catch {
        return error
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class PolymorphismTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testAUnionMemberPerId() async throws {
        let photo = try await client.queries.attachment(id: "ph1").attachment
        let video = try await client.queries.attachment(id: "v1").attachment
        let document = try await client.queries.attachment(id: "d1").attachment
        XCTAssertEqual((photo as? Photo)?.width, 640)
        XCTAssertEqual((video as? Video)?.seconds, 30)
        XCTAssertEqual((document as? Document)?.pages, 12)
    }

    func testANullableUnionDecodesNil() async throws {
        let missing = try await client.queries.attachment(id: "nope").attachment
        XCTAssertNil(missing)
    }

    func testAListOfUnionMembers() async throws {
        let list = try await client.queries.attachments().attachments
        XCTAssertEqual(kinds(list), ["Photo", "Video", "Document"])
    }

    func testNullElementsInAListOfUnions() async throws {
        let list = try await client.queries.attachmentsNullable().attachmentsNullable
        XCTAssertEqual(kinds(try XCTUnwrap(list)), ["Photo", "nil", "Document"])
    }

    func testAUnionReturnedByAMutation() async throws {
        for (kindName, expected) in [("photo", "Photo"), ("video", "Video"), ("document", "Document")] {
            let created = try await client.mutations.addAttachment(articleId: "a1", url: "u", kind: kindName).addAttachment
            XCTAssertEqual(kind(created), expected, kindName)
        }
    }

    func testAServerErrorOnAUnionMutationThrows() async throws {
        let error = await failure { try await self.client.mutations.addAttachment(articleId: "a1", url: "u", kind: "bogus") }
        XCTAssertNotNil(error)
    }

    func testAListOfAnInterfaceImplementingAnotherInterface() async throws {
        let feed = try await client.queries.feed().feed
        XCTAssertEqual(kinds(feed), ["Article", "Comment", "Article", "Comment"])
        XCTAssertEqual(feed.map { $0.createdBy }, ["alice", "bob", "bob", "alice"])
    }

    func testANullableInterfaceReturnsEachImplementationOrNil() async throws {
        let article = try await client.queries.node(id: "a1").node
        let comment = try await client.queries.node(id: "c1").node
        let missing = try await client.queries.node(id: "zzz").node
        XCTAssertTrue(article is Article)
        XCTAssertTrue(comment is Comment)
        XCTAssertNil(missing)
    }

    func testAUnionFieldAndAListOfUnionsInsideAnObject() async throws {
        let article = try await client.queries.article(id: "a1").article
        XCTAssertTrue(article.cover is Photo)
        XCTAssertEqual(kinds(article.attachments), ["Photo", "Video", "Document"])
    }

    func testNullPolymorphicFields() async throws {
        let article = try await client.queries.article(id: "a2").article
        XCTAssertNil(article.cover)
        XCTAssertTrue(article.attachments.isEmpty)
        XCTAssertNil(article.related)
    }

    func testNullElementsInAListOfInterfaces() async throws {
        let related = try await client.queries.article(id: "a1").article.related
        XCTAssertEqual(kinds(try XCTUnwrap(related)), ["Comment", "nil"])
    }

    func testAnInterfaceFieldPointingBackAtAnImplementer() async throws {
        let feed = try await client.queries.feed().feed
        let reply = try XCTUnwrap(feed[3] as? Comment)
        let parent = try XCTUnwrap(reply.parent as? Article)
        XCTAssertEqual(parent.title, "Hello")
    }

    func testAnUnknownArticleIsAnError() async throws {
        let error = await failure { try await self.client.queries.article(id: "zzz") }
        XCTAssertNotNil(error)
    }

    func testCapturedErrorsOnAUnionOperation() async throws {
        let ok = try await client.queries.attachmentOrErrors(id: "ph1")
        XCTAssertNil(ok.errors)
        XCTAssertTrue(ok.data?.attachmentOrErrors is Photo)
        let failed = try await client.queries.attachmentOrErrors(id: "boom")
        XCTAssertNil(failed.data?.attachmentOrErrors)
        XCTAssertFalse(try XCTUnwrap(failed.errors).first?.message.isEmpty ?? true)
    }

    func testACachedUnionOperationIsServedOnce() async throws {
        let calls = CallCounter()
        let real = DefaultGraphLinkURLSessionAdapter(url: Fixtures.SERVER_URL)
        let multipart = DefaultGraphLinkURLSessionMultipartAdapter(url: Fixtures.UPLOAD_URL)
        let counting = GraphLinkClient(
            adapter: { payload in
                calls.increment()
                return try await real.execute(payload)
            },
            wsAdapter: DefaultGraphLinkWebSocketAdapter(url: Fixtures.WS_URL),
            multipartAdapter: multipart.executeMultipart
        )
        let first = try await counting.queries.getCachedAttachment(id: "v1").getCachedAttachment
        let second = try await counting.queries.getCachedAttachment(id: "v1").getCachedAttachment
        XCTAssertTrue(first is Video)
        XCTAssertTrue(second is Video)
        XCTAssertEqual(calls.count, 1)
    }
}
