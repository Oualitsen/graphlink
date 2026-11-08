import Foundation
import XCTest
@testable import GraphLinkGenerated

final class ScalarCodecTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testCodecScalarIsDecodedInAResponse() async throws {
        let bag = try await client.queries.scalarFixture().scalarFixture
        XCTAssertEqual(bag.opaque, "opaque:o-1")
    }

    func testCodecScalarIsEncodedInAnInputFieldAndDecodedAgain() async throws {
        let input = ScalarsInput(dt: "x", long: 1, opaque: "opaque:xyz", dts: [])
        let bag = try await client.queries.echoScalars(input: input).echoScalars
        XCTAssertEqual(bag.opaque, "opaque:xyz")
    }

    func testCodecScalarIsEncodedInAnOperationArgumentAndDecodedAgain() async throws {
        let bag = try await client.queries.echoScalarArgs(dt: "x", opaque: "opaque:abc", dts: []).echoScalarArgs
        XCTAssertEqual(bag.opaque, "opaque:abc")
    }

    func testCodecScalarKeepsNullAsNull() async throws {
        let fromArgs = try await client.queries.echoScalarArgs(dt: "x", dts: []).echoScalarArgs
        XCTAssertNil(fromArgs.opaque)
        let fromInput = try await client.queries.echoScalars(input: ScalarsInput(dt: "x", long: 1, dts: [])).echoScalars
        XCTAssertNil(fromInput.opaque)
    }

    func testAliasScalarsKeepLongPrecisionAndStringPassThrough() async throws {
        let bag = try await client.queries.scalarFixture().scalarFixture
        XCTAssertEqual(bag.long, 9007199254740993)
        XCTAssertEqual(bag.longs, [1, nil, 9223372036854775807])
        XCTAssertEqual(bag.dt, "2026-01-02T03:04:05Z")
    }

    func testLongDefaultReachesTheServer() async throws {
        let bag = try await client.queries.echoScalarArgs(dt: "x", dts: []).echoScalarArgs
        XCTAssertEqual(bag.long, 9007199254740993)
    }

    func testCodecScalarOfTheWrongTypeThrowsInsteadOfCrashing() async {
        for wire in [7, true, 1.5, ["a": 1], ["a"]] as [Any] {
            let adapter = MockAdapter()
            adapter.registerData("scalarFixture", n(("scalarFixture", n(("dt", "x"), ("long", 1), ("dts", []), ("opaque", wire)))))
            let client = Fixtures.newClient(adapter, MockWebSocketAdapter())
            do {
                _ = try await client.queries.scalarFixture()
                XCTFail("a \(wire) was accepted for an Opaque")
            } catch let error as GraphLinkDecodeError {
                XCTAssertTrue(error.message.contains("opaque"), error.message)
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testCodecScalarOfTheRightTypeStillRunsTheTemplate() async throws {
        let adapter = MockAdapter()
        adapter.registerData("scalarFixture", n(("scalarFixture", n(("dt", "x"), ("long", 1), ("dts", []), ("opaque", "abc")))))
        let client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        let bag = try await client.queries.scalarFixture().scalarFixture
        XCTAssertEqual(bag.opaque, "opaque:abc")
    }
}
