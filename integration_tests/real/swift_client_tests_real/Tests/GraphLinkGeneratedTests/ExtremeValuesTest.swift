import Foundation
import XCTest
@testable import GraphLinkGenerated

final class ExtremeValuesTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testIntAtBoth32BitLimits() async throws {
        let r = try await client.queries.echoEverything(input: EverythingInput(i: 2147483647, neg: -2147483648)).echoEverything
        XCTAssertEqual([r.i, r.neg], [2147483647, -2147483648])
    }

    func testFloatAt1e308AndNegativeZero() async throws {
        let r = try await client.queries.echoEverything(input: EverythingInput(f: 1e308, exp: -0.0)).echoEverything
        XCTAssertEqual(r.f, 1e308)
        // JSONSerialization writes -0.0 as "-0", an integer literal, and the server reads it back as 0.
        XCTAssertEqual(r.exp?.sign, .plus)
    }

    func testAStringWithANulCharacter() async throws {
        let r = try await client.queries.echoEverything(input: EverythingInput(s: "a\u{0000}b")).echoEverything
        XCTAssertEqual(r.s, "a\u{0000}b")
    }

    // A Swift String cannot hold a lone surrogate: invalid UTF-8 decodes to U+FFFD before it is sent.
    func testInvalidUtf8BecomesTheReplacementCharacter() async throws {
        let sent = String(decoding: [0x78, 0xED, 0xA0, 0x80, 0x79], as: UTF8.self)
        let r = try await client.queries.echoEverything(input: EverythingInput(s: sent)).echoEverything
        XCTAssertEqual(r.s, sent)
    }
}
