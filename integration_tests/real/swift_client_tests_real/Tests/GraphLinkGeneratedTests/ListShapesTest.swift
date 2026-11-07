import Foundation
import XCTest
@testable import GraphLinkGenerated

private let known: [Spelling] = [.a, .b2, .xY, .http2Ok, .v1, .snakeCase2]

private func typeName(_ value: Any?) -> String? {
    value.map { String(describing: type(of: $0)) }
}

final class ListShapesTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    private func shapes(_ mode: String) async throws -> ListShapes {
        try await client.queries.listShapes(mode: mode).listShapes
    }

    func testScalarsWithNulls() async throws {
        let s = try await shapes("full")
        XCTAssertEqual(s.a, [1, 2, 3])
        XCTAssertEqual(s.b, [1, 2, 3])
        XCTAssertEqual(s.c, [1, nil, 3])
        XCTAssertEqual(s.d, [nil])
    }

    func testNestedLists() async throws {
        let s = try await shapes("full")
        XCTAssertEqual(s.e, [[1, 2], [3]])
        XCTAssertEqual(s.f, [[1, nil], nil])
    }

    func testEnumsWithNulls() async throws {
        let actual = try await shapes("full").g
        XCTAssertEqual(actual, [.a, nil, .b2])
    }

    func testObjectsUnionsAndInterfaces() async throws {
        let s = try await shapes("full")
        XCTAssertEqual(s.h.map { $0?.width }, [640, nil])
        XCTAssertEqual(s.i.map { typeName($0) }, ["Photo", nil, "Video"])
        XCTAssertEqual(s.j.map { typeName($0) }, ["Comment", nil])
    }

    func testEmptyListsStayEmpty() async throws {
        let s = try await shapes("empty")
        XCTAssertEqual(s.b, [])
        XCTAssertEqual(s.d, [])
        XCTAssertEqual(s.f, [])
        XCTAssertEqual(s.e, [])
    }

    func testNullListsStayNullWhileRequiredOnesAreEmpty() async throws {
        let s = try await shapes("null")
        XCTAssertNil(s.b)
        XCTAssertNil(s.d)
        XCTAssertNil(s.f)
        XCTAssertTrue(s.a.isEmpty && s.g.isEmpty && s.i.isEmpty)
    }

    func testListArgumentsRoundTrip() async throws {
        let r = try await client.queries.echoArgs(
            a: [1, 2], b: [1, nil], c: [[1], [], [2, 3]], e: [.xY, .http2Ok], f: [nil, .v1]
        ).echoArgs
        XCTAssertEqual(r.a, [1, 2])
        XCTAssertEqual(r.b, [1, nil])
        XCTAssertEqual(r.c, [[1], [], [2, 3]])
        XCTAssertEqual(r.e, [.xY, .http2Ok])
        XCTAssertEqual(r.f, [nil, .v1])
    }

    func testOmittedListsAreNullAndDefaultsApply() async throws {
        let r = try await client.queries.echoArgs(a: [], e: []).echoArgs
        XCTAssertNil(r.b)
        XCTAssertNil(r.c)
        XCTAssertNil(r.f)
        XCTAssertEqual(r.g, [.a, .b2])
        XCTAssertEqual(r.one, .only)
    }

    func testExplicitlyEmptyDefaultBearingListIsKept() async throws {
        let actual = try await client.queries.echoArgs(a: [], e: [], g: []).echoArgs.g
        XCTAssertEqual(actual, [])
    }

    func testExplicitNullOverridesTheDefault() async throws {
        let actual = try await client.queries.echoArgs(a: [], e: [], g: nil).echoArgs.g
        XCTAssertNil(actual)
    }

    func testListInputFieldsRoundTrip() async throws {
        let input = ListsInput(a: [3, 4], b: [nil, 5], c: [[1, 2], []], e: [.snakeCase2], f: [.a, nil], g: [.v1])
        let r = try await client.queries.echoInput(input: input).echoInput
        XCTAssertEqual(r.a, [3, 4])
        XCTAssertEqual(r.b, [nil, 5])
        XCTAssertEqual(r.c, [[1, 2], []])
        XCTAssertEqual(r.e, [.snakeCase2])
        XCTAssertEqual(r.f, [.a, nil])
        XCTAssertEqual(r.g, [.v1])
    }

    func testInputDefaultsReachTheServer() async throws {
        let r = try await client.queries.echoInput(input: ListsInput(a: [], e: [])).echoInput
        XCTAssertEqual(r.g, [.a, .b2])
        XCTAssertEqual(r.one, .only)
    }

    func testLargeListOfScalars() async throws {
        let r = try await client.queries.bigInts(n: 50000).bigInts
        XCTAssertEqual(r.count, 50000)
        XCTAssertEqual(r.last, 49999)
    }

    func testLargeListOfObjects() async throws {
        let r = try await client.queries.bigPhotos(n: 20000).bigPhotos
        XCTAssertEqual(r.count, 20000)
        XCTAssertEqual(r.last?.id, "p19999")
        XCTAssertEqual(r.last?.width, 19999)
    }

    func testEverySpellingRoundTrips() async throws {
        let actual = try await client.queries.echoArgs(a: [], e: known).echoArgs.e
        XCTAssertEqual(actual, known)
    }

    func testWireNamesAreTheDeclaredOnes() {
        XCTAssertEqual(known.map { $0.toJson() }, ["A", "B2", "x__y", "http2_ok", "v1", "snake_case_2"])
    }

    func testEnumUsedOnlyAsArgument() async throws {
        let actual = try await client.queries.argOnly(v: .p2).argOnly
        XCTAssertEqual(actual, "P2")
    }

    func testEnumUsedOnlyInResponse() async throws {
        let actual = try await client.queries.respOnly().respOnly
        XCTAssertEqual(actual, .r2)
    }

    func testUnknownEnumValueInAField() async throws {
        let p = try await client.queries.phaseProbe().phaseProbe
        XCTAssertEqual(p.single, .unknownValue__)
        XCTAssertEqual(p.maybe, .unknownValue__)
    }

    func testUnknownEnumValueInListElements() async throws {
        let p = try await client.queries.phaseProbe().phaseProbe
        XCTAssertEqual(p.list, [.open, .unknownValue__, .closed])
        XCTAssertEqual(p.nullableList, [.unknownValue__, nil])
    }

    func testUnknownEnumValueInAUnionMember() async throws {
        let h = try await client.queries.phaseHolder().phaseHolder
        XCTAssertEqual((h as? Phased)?.phase, .unknownValue__)
    }
}
