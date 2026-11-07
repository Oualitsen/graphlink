import Foundation
import XCTest
@testable import GraphLinkGenerated

private func v(_ wire: String) -> String { "v:\(wire)" }

final class IdentifiersTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    private func assertEchoed(_ r: Reserved) {
        let fields: [String: String] = [
            "type": r.type, "default": r.default_, "in": r.in_, "is": r.is_, "var": r.var_, "val": r.val,
            "fun": r.fun, "new": r.new, "import": r.import_, "return": r.return_, "object": r.object,
            "from": r.from, "None": r.none, "True": r.true_, "func": r.func_, "range": r.range,
            "self": r.self_, "Self": r.self2, "init": r.init_, "Type": r.type2, "Protocol": r.protocol_,
            "async": r.async, "await": r.await_, "package": r.package, "interface": r.interface,
            "enum": r.enum_, "null": r.null,
        ]
        XCTAssertEqual(fields.count, 27)
        for (wire, value) in fields { XCTAssertEqual(value, v(wire), wire) }
    }

    func testReservedWordsAsArgumentNames() async throws {
        let r = try await client.queries.reservedEcho(
            type: v("type"), default_: v("default"), in_: v("in"), is_: v("is"), var_: v("var"), val: v("val"),
            fun: v("fun"), new: v("new"), import_: v("import"), return_: v("return"), object: v("object"),
            from: v("from"), none: v("None"), true_: v("True"), func_: v("func"), range: v("range"),
            self_: v("self"), self2: v("Self"), init_: v("init"), type2: v("Type"), protocol_: v("Protocol"),
            async: v("async"), await_: v("await"), package: v("package"), interface: v("interface"),
            enum_: v("enum"), null: v("null")
        ).reservedEcho
        assertEchoed(r)
    }

    func testReservedWordsAsInputAndResponseFields() async throws {
        let input = ReservedInput(
            type: v("type"), default_: v("default"), in_: v("in"), is_: v("is"), var_: v("var"), val: v("val"),
            fun: v("fun"), new: v("new"), import_: v("import"), return_: v("return"), object: v("object"),
            from: v("from"), none: v("None"), true_: v("True"), func_: v("func"), range: v("range"),
            self_: v("self"), self2: v("Self"), init_: v("init"), type2: v("Type"), protocol_: v("Protocol"),
            async: v("async"), await_: v("await"), package: v("package"), interface: v("interface"),
            enum_: v("enum"), null: v("null")
        )
        assertEchoed(try await client.queries.reservedEchoInput(input: input).reservedEchoInput)
    }

    func testReservedWordsAsOperationNames() async throws {
        let a = try await client.queries.import_(value: "a").import_
        let b = try await client.queries.default_(value: "b").default_
        let c = try await client.queries.new(value: "c").new
        let d = try await client.queries.func_(value: "d").func_
        let e = try await client.queries.none(value: "e").none
        let f = try await client.queries.self_(value: "f").self_
        XCTAssertEqual([a, b, c, d, e, f], ["a", "b", "c", "d", "e", "f"])
    }

    private let literals: [Literal] = [.default_, .class_, .none, .true_, .nil_, .undefined, .naN, .self_]

    func testLiteralLookingEnumValuesDecode() async throws {
        let actual = try await client.queries.literals().literals
        XCTAssertEqual(actual, literals)
    }

    func testLiteralLookingEnumValuesRoundTrip() async throws {
        for value in literals {
            let echoed = try await client.queries.literalEcho(v: value, all: literals).literalEcho
            XCTAssertEqual(echoed, value)
        }
    }

    func testStdlibClashingTypeNames() async throws {
        let c = try await client.queries.clashes().clashes
        XCTAssertEqual(
            [c.error.id, c.response.id, c.request.id, c.list.id, c.map.id, c.object.id, c.optional.id, c.date.id, c.result.id, c.void.id],
            ["error-1", "response-1", "request-1", "list-1", "map-1", "object-1", "optional-1", "date-1", "result-1", "void-1"]
        )
    }

    func testOddNamesRoundTrip() async throws {
        let input = OddInput(
            userId2: "user_id", userId: "userId", urlValue: "URLValue", httpServer: "HTTPServer",
            leading: "_leading", trailing: "trailing_", v2Name: "v2_name", isActive: "isActive",
            active: "active", getX: "getX", x: "x"
        )
        let r = try await client.queries.oddEcho(input: input).oddEcho
        XCTAssertEqual(
            [r.userId2, r.userId, r.urlValue, r.httpServer, r.leading, r.trailing, r.v2Name, r.isActive, r.active, r.getX, r.x],
            ["user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_", "v2_name", "isActive", "active", "getX", "x"]
        )
    }
}
