import Foundation
import XCTest
@testable import GraphLinkGenerated

final class LiteralsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    private func assertNasty(_ r: NastyEcho) {
        XCTAssertEqual(r.dollar, "cost $5 and ${x} and $$")
        XCTAssertEqual(r.quote, "say \"hi\" it's")
        XCTAssertEqual(r.backslash, "C:\\dir\\file\\n")
        XCTAssertEqual(r.newline, "line1\nline2\ttab")
        XCTAssertEqual(r.percent, "100% {braces} {{x}} %s %d")
        XCTAssertEqual(r.comments, "a */ b // c /* d")
        XCTAssertEqual(r.triple, "\"\"\" ''' ```")
        XCTAssertEqual(r.unicode, "café 中 😀")
        XCTAssertEqual(r.nonAscii, "é中😀")
    }

    func testStringDefaultsOnOperationArguments() async throws {
        let r = try await client.queries.echoNastyArgs().echoNastyArgs
        assertNasty(r)
    }

    func testStringDefaultsOnInputFieldsThroughAnInputDefaultingToEmptyObject() async throws {
        let r = try await client.queries.echoNasty().echoNasty
        assertNasty(r)
    }

    func testAnExplicitValueReplacesTheDefault() async throws {
        let r = try await client.queries.echoNastyArgs(dollar: "$y").echoNastyArgs
        XCTAssertEqual(r.dollar, "$y")
        XCTAssertEqual(r.quote, "say \"hi\" it's")
    }

    func testStringLiteralsWrittenInlineInAnOperation() async throws {
        let r = try await client.queries.nastyLiteral().echoNastyArgs
        XCTAssertEqual(r.dollar, "cost $5 ${x}")
        XCTAssertEqual(r.quote, "say \"hi\"")
        XCTAssertEqual(r.backslash, "C:\\dir")
        XCTAssertEqual(r.newline, "a\nb")
        XCTAssertEqual(r.unicode, "é😀")
        XCTAssertEqual(r.triple, "block \"x\" ")
    }

    func testDefaultsOfEveryKind() async throws {
        let r = try await client.queries.echoEverything(input: EverythingInput()).echoEverything
        XCTAssertEqual([r.i, r.neg, r.big], [42, -7, 2147483647])
        XCTAssertEqual([r.f, r.exp], [3.14, 1000.0])
        XCTAssertEqual([r.b, r.bf], [true, false])
        XCTAssertEqual([r.s, r.id], ["x", "abc"])
        XCTAssertEqual(r.e, .xY)
        XCTAssertEqual(r.ints, [1, 2, 3])
        XCTAssertEqual(r.nested, [[1], [2, 3]])
        XCTAssertEqual(r.inner?.n, 5)
        XCTAssertEqual(r.inner?.label, "inner")
        XCTAssertNil(r.nothing)
        XCTAssertEqual(r.emptyList, [])
        XCTAssertEqual(r.emptyObj?.n, 1)
        XCTAssertEqual(r.emptyObj?.label, "dflt")
    }

    func testAnArgumentWhoseInputTypeHasItsOwnDefaults() async throws {
        let r = try await client.queries.echoInner().echoInner
        XCTAssertEqual(r.n, 9)
        XCTAssertEqual(r.label, "dflt")
        XCTAssertEqual(r.tags, ["a"])
    }

    func testRecursiveTree() async throws {
        let tree = Tree(value: 1, children: [Tree(value: 2, children: [Tree(value: 4)]), Tree(value: 3)])
        let r = try await client.queries.treeStats(tree: tree).treeStats
        XCTAssertEqual(r.flat, [1, 2, 4, 3])
        XCTAssertEqual(r.depth, 3)
    }

    func testMutuallyRecursiveInputs() async throws {
        let ping = Ping(n: 1, pong: Pong(n: 2, ping: Ping(n: 3)))
        let length = try await client.queries.pingLength(ping: ping).pingLength
        XCTAssertEqual(length, 3)
    }

    func testOneOfInput() async throws {
        let cat = try await client.queries.describePet(pet: Pet(cat: "Tom")).describePet
        let dog = try await client.queries.describePet(pet: Pet(dog: 3)).describePet
        XCTAssertEqual([cat, dog], ["cat:Tom", "dog:3"])
    }

    func testDeprecatedFieldsArgumentsAndEnumValuesStillWork() async throws {
        let r = try await client.queries.legacy(withReason: "a", plain: "b").legacy
        XCTAssertEqual(r.old, "a")
        XCTAssertEqual(r.older, "b")
        XCTAssertEqual(r.mood, .calm)
    }
}
