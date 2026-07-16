import XCTest
@testable import GraphLinkGenerated

final class NestingTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testEnumListDepths123() async throws {
        let c1 = try await client.queries.colors1().colors1
        XCTAssertEqual(c1, [Color.red, Color.green, Color.blue])

        let c2 = try await client.queries.colors2().colors2
        XCTAssertEqual(c2, [[Color.red], [Color.green, Color.blue]])

        let c3 = try await client.queries.colors3().colors3
        XCTAssertEqual(c3, [[[Color.red]]])
    }

    func testTypeListDepths123() async throws {
        let b1 = try await client.queries.boxes1().boxes1
        XCTAssertEqual(b1?.count, 2)

        let b2 = try await client.queries.boxes2().boxes2
        XCTAssertEqual(b2.count, 2)

        let b3 = try await client.queries.boxes3().boxes3
        let b3Level1 = b3!
        let b3Level2 = b3Level1.first!!
        let b3Level3 = b3Level2.first!!
        let b3Level4 = b3Level3.first!!
        XCTAssertEqual(b3Level4.id, "b1")
    }

    func testInterfaceListDepths123() async throws {
        let s1 = try await client.queries.shapes1().shapes1
        let kinds = Set(s1.map { $0.kind })
        XCTAssertTrue(kinds.isSuperset(of: ["circle", "square"]))

        let s3 = try await client.queries.shapes3().shapes3
        XCTAssertNotNil(s3.first!.first!.first!.kind)
    }

    func testUnionListDepths123() async throws {
        let m1 = try await client.queries.media1().media1
        XCTAssertEqual(m1.count, 2)
        let photos = m1.compactMap { $0 as? Photo }
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first!.width, 640)
        let videos = m1.compactMap { $0 as? Video }
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos.first!.durationSec, 30)

        let m3 = try await client.queries.media3().media3
        XCTAssertNotNil(m3.first!.first!.first!.url)
    }
}
