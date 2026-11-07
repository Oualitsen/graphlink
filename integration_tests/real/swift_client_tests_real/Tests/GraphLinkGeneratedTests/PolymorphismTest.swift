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
    case is Album: return "Album"
    case is Playlist: return "Playlist"
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

    func testTheFieldArgumentReachesEveryImplementerAndEachKeepsItsOwnFields() async throws {
        let albumResponse = try await client.queries.listing(id: "al1", fieldArgs: ListingFieldArgs(itemsLimit: 2))
        let album = try XCTUnwrap(albumResponse.listing as? Album)
        XCTAssertEqual(album.year, 2020)
        XCTAssertEqual(kinds(album.items), ["Photo", "Video"])
        let playlistResponse = try await client.queries.listing(id: "pl1", fieldArgs: ListingFieldArgs(itemsLimit: 5))
        let playlist = try XCTUnwrap(playlistResponse.listing as? Playlist)
        XCTAssertEqual(playlist.tracks, 12)
        XCTAssertEqual(kinds(playlist.items), ["Video", "Document"])
    }

    func testALimitOfZeroYieldsEmptyLists() async throws {
        let listingResponse = try await client.queries.listing(id: "al1", fieldArgs: ListingFieldArgs(itemsLimit: 0))
        let listing = try XCTUnwrap(listingResponse.listing)
        XCTAssertTrue(listing.items.isEmpty)
    }

    func testTheInterfaceFieldReturnsTheOtherImplementerOrNil() async throws {
        let summerResponse = try await client.queries.listing(id: "al1", fieldArgs: ListingFieldArgs(itemsLimit: 1))
        let summer = try XCTUnwrap(summerResponse.listing)
        XCTAssertEqual((summer.related as? Playlist)?.tracks, 12)
        let winterResponse = try await client.queries.listing(id: "al2", fieldArgs: ListingFieldArgs(itemsLimit: 1))
        let winter = try XCTUnwrap(winterResponse.listing)
        XCTAssertNil(winter.related)
    }

    func testAnUnknownListingIdDecodesNil() async throws {
        let response = try await client.queries.listing(id: "nope", fieldArgs: ListingFieldArgs(itemsLimit: 1))
        XCTAssertNil(response.listing)
    }

    func testAListOfTheInterfaceDecodesEachImplementer() async throws {
        let listings = try await client.queries.listings(fieldArgs: ListingsFieldArgs(itemsLimit: 1)).listings
        XCTAssertEqual(kinds(listings), ["Album", "Playlist", "Album"])
        XCTAssertEqual(listings.map { $0.items.count }, [1, 1, 1])
    }

    func testASingleMemberUnionDecodesToTheMember() async throws {
        let soloResponse = try await client.queries.solo(fieldArgs: SoloFieldArgs(itemsLimit: 1))
        let solo = try XCTUnwrap(soloResponse.solo as? Album)
        XCTAssertEqual(solo.title, "Summer")
    }

    func testIdAndUrlAreReadableOnTheUnionItself() async throws {
        let list = try await client.queries.attachments().attachments
        XCTAssertEqual(list.map { $0.id }, ["ph1", "v1", "d1"])
        XCTAssertEqual(list.map { $0.url }, ["http://cdn/1.png", "http://cdn/1.mp4", "http://cdn/1.pdf"])
    }

    func testASelectionThatSharesOnlySomeFieldsExposesJustThose() async throws {
        let photo = try await client.queries.fetchPhotoParts(id: "ph1").attachment
        XCTAssertEqual(photo?.id, "ph1")
        let video = try await client.queries.fetchPhotoParts(id: "v1").attachment
        XCTAssertEqual(video?.id, "v1")
    }

    func testAUnionOfTwoTypesSharesOnlyId() async throws {
        let photo = try await client.queries.shareable(id: "ph1").shareable
        XCTAssertEqual(photo?.id, "ph1")
        let phone = try await client.queries.shareable(id: "p1").shareable
        XCTAssertEqual(phone?.id, "p1")
    }

    func testTheDirectQueryKeepsTheFullType() async throws {
        let photo = try await client.queries.photo(id: "ph1").photo
        XCTAssertEqual(photo?.id, "ph1")
        XCTAssertEqual(photo?.url, "http://cdn/1.png")
        XCTAssertEqual(photo?.width, 640)
        let missing = try await client.queries.photo(id: "nope").photo
        XCTAssertNil(missing)
    }

    func testAPartialSelectionOfTheSameTypeDoesNotReplaceIt() async throws {
        let width = try await client.queries.fetchPhotoWidth(id: "ph1").photo
        XCTAssertEqual(width?.width, 640)
        let member = try await client.queries.fetchPhotoUrl(id: "ph1").attachment
        XCTAssertEqual((member as? Photo_Url)?.url, "http://cdn/1.png")
        let video = try await client.queries.fetchPhotoUrl(id: "v1").attachment
        XCTAssertTrue(video is Video_Id)
    }

    func testAnInterfaceFragmentMixedWithConcreteOnes() async throws {
        let results = try await client.queries.searchMixed(term: "x").search
        XCTAssertEqual(results.map { $0.id }, ["user-1", "post-1"])
        XCTAssertEqual((results[0] as? UserResult_IdName)?.name, "Alice Smith")
        XCTAssertEqual((results[1] as? PostResult)?.title, "Hello World")
    }

    private func nodeTitle() async throws -> String? {
        let node = try await client.queries.getCachedNode(id: "a1").getCachedNode
        return (node as? Article)?.title
    }

    private func videoSeconds() async throws -> Int? {
        let attachment = try await client.queries.getCachedAttachment(id: "v1").getCachedAttachment
        return (attachment as? Video)?.seconds
    }

    func testACachedInterfaceResultIsServedFromTheCache() async throws {
        let first = try await nodeTitle()
        let second = try await nodeTitle()
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testInvalidatingTheTagOfACachedInterfaceFetchesItAgain() async throws {
        let before = try await nodeTitle()
        _ = try await client.mutations.evictNodes()
        let after = try await nodeTitle()
        XCTAssertNotEqual(before, after)
    }

    func testInvalidatingTheTagOfACachedUnionFetchesItAgain() async throws {
        let before = try await videoSeconds()
        let cached = try await videoSeconds()
        XCTAssertEqual(before, cached)
        _ = try await client.mutations.evictAttachments()
        let after = try await videoSeconds()
        XCTAssertNotEqual(before, after)
    }

    func testInvalidatingAnotherTagLeavesTheCachedUnionAlone() async throws {
        let before = try await videoSeconds()
        _ = try await client.mutations.evictNodes()
        let after = try await videoSeconds()
        XCTAssertEqual(before, after)
    }
}
