import XCTest
@testable import GraphLinkGenerated

final class KeywordsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testReservedWordFieldsRoundTripBothDartOnlyJavaOnly() async throws {
        let r = try await client.queries.reserved().reserved
        XCTAssertEqual(r.class_, "cls")
        XCTAssertEqual(r.return_, 42)
        XCTAssertTrue(r.new)
        XCTAssertEqual(r.default_, "def")
        XCTAssertEqual(r.is_, "yes")
        XCTAssertEqual(r.in_, "inside")
        XCTAssertEqual(r.with, "w")
        XCTAssertEqual(r.int, 7)
        XCTAssertFalse(r.synchronized)
        XCTAssertEqual(r.native, "n")
        XCTAssertEqual(r.kind, Keyword.class_)
        XCTAssertEqual(r.nested.value, "v")
        XCTAssertEqual(r.secret.token, "tok")
    }

    func testReservedOperationNamePlusReservedArgumentNames() async throws {
        let res = try await client.queries.switch_(class_: "x", return_: 5)
        XCTAssertEqual(res.switch_.class_, "x")
        XCTAssertEqual(res.switch_.return_, 5)
    }

    func testLeadingUnderscoreOperation() async throws {
        let res = try await client.queries.status()
        XCTAssertEqual(res.status, "ok")
    }

    func testCollidingFieldNamesStayDistinct() async throws {
        let c = try await client.queries.collide().collide
        XCTAssertTrue([c.class_2, c.class2].contains("A"))
        XCTAssertTrue([c.class_2, c.class2].contains("B"))
    }

    func testReservedWordInputFieldsMutation() async throws {
        let res = try await client.mutations.echoReserved(
            input: ReservedInput(class_: "X", return_: 5, default_: "D", is_: true, synchronized: 3)
        )
        XCTAssertEqual(res.echoReserved.class_, "X")
        XCTAssertEqual(res.echoReserved.return_, 5)
        XCTAssertEqual(res.echoReserved.default_, "D")
    }
}
