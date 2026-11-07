import Foundation
import XCTest
@testable import GraphLinkGenerated

final class CustomOperationsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testAFragmentThatSpreadsAnotherFragment() async throws {
        let u = try await client.queries.fragNested(id: "user-1").getUser
        XCTAssertEqual([u.id, u.name], ["user-1", "Alice Smith"])
        XCTAssertEqual(u.status, .active)
    }

    func testOneFragmentReusedByTwoOperations() async throws {
        let ids = try await client.queries.fragReuseA().listUsers.map { $0.id }
        XCTAssertTrue(Set(ids).isSuperset(of: ["user-1", "user-2"]))
        let one = try await client.queries.fragReuseB(id: "user-2").getUser
        XCTAssertEqual([one.id, one.name], ["user-2", "Bob Jones"])
        XCTAssertFalse(one.email.isEmpty)
    }

    func testAFragmentOnAnInterfaceNextToAnInlineFragment() async throws {
        let feed = try await client.queries.fragOnInterface().feed
        XCTAssertFalse(feed.isEmpty)
        XCTAssertTrue(feed.allSatisfy { !$0.id.isEmpty && !$0.createdBy.isEmpty })
    }

    func testSeveralRootFieldsSharingOneFragment() async throws {
        let r = try await client.queries.multiRoot()
        XCTAssertEqual(r.first.name, "Alice Smith")
        XCTAssertEqual(r.second.name, "Bob Jones")
        XCTAssertTrue(Set(r.all.map { $0.id }).isSuperset(of: ["user-1", "user-2"]))
    }

    func testVariableDefaultsApplyWhenNotGiven() async throws {
        let r = try await client.queries.varsDefaults().searchUsers
        XCTAssertEqual(r.count, 1)
    }

    func testAnExplicitValueReplacesTheVariableDefault() async throws {
        let r = try await client.queries.varsDefaults(limit: 5, name: "Alice").searchUsers
        XCTAssertEqual(r.map { $0.id }, ["user-1"])
    }

    func testListNestedListAndEnumVariables() async throws {
        let r = try await client.queries.varsLists(a: [1, 2], b: [1, nil], c: [[1], [2, 3]], e: [.xY], f: [nil, .v1]).echoArgs
        XCTAssertEqual(r.a, [1, 2])
        XCTAssertEqual(r.b, [1, nil])
        XCTAssertEqual(r.c, [[1], [2, 3]])
        XCTAssertEqual(r.e, [.xY])
        XCTAssertEqual(r.f, [nil, .v1])
    }

    func testANullableEnumVariable() async throws {
        let one = try await client.queries.varsEnum(one: .only).echoArgs.one
        XCTAssertEqual(one, .only)
    }

    func testAnInputObjectVariable() async throws {
        let r = try await client.queries.varsInput(inner: InnerInput(n: 4, label: "x")).echoInner
        XCTAssertEqual(r.n, 4)
        XCTAssertEqual(r.label, "x")
    }

    func testNullableVersusNonNullVariables() async throws {
        let given = try await client.queries.varsNullable(dollar: "$d", quote: "q").echoNastyArgs
        XCTAssertEqual(given.dollar, "$d")
        XCTAssertEqual(given.quote, "q")
        let left = try await client.queries.varsNullable(quote: "q").echoNastyArgs
        XCTAssertNil(left.dollar)
        XCTAssertEqual(left.quote, "q")
    }

    func testIncludeAndSkipWithVariables() async throws {
        let both = try await client.queries.conditionalVars(withEmail: true, skipName: false).getUser
        XCTAssertEqual(both.id, "user-1")
        XCTAssertEqual(both.name, "Alice Smith")
        XCTAssertEqual(both.email, "alice@test.com")
        let neither = try await client.queries.conditionalVars(withEmail: false, skipName: true).getUser
        XCTAssertEqual(neither.id, "user-1")
        XCTAssertNil(neither.name)
        XCTAssertNil(neither.email)
    }

    func testIncludeAndSkipWithLiterals() async throws {
        let u = try await client.queries.conditionalLiterals().getUser
        XCTAssertEqual(u.name, "Alice Smith")
        XCTAssertNil(u.email)
        XCTAssertEqual(u.status, .active)
        XCTAssertNil(u.priority)
    }

    func testAliases() async throws {
        let r = try await client.queries.aliasesSameField()
        XCTAssertEqual([r.a.id, r.b.id], ["user-1", "user-2"])
        let k = try await client.queries.aliasKeywords().class_
        XCTAssertEqual([k.default_, k.import_], ["Alice Smith", "user-1"])
        let name = try await client.queries.aliasEqualsOtherField().getUser.name
        XCTAssertEqual(name, "alice@test.com")
    }

    func testOperationNamesThatCollide() async throws {
        let user = try await client.queries.user().getUser.id
        let photo = try await client.queries.photo2().photo?.id
        let keyword = try await client.queries.return_().listUsers.count
        let shelf = try await client.queries.shelf().shelf.id
        let response = try await client.queries.getUserResponse().getUser.id
        XCTAssertEqual(user, "user-1")
        XCTAssertEqual(photo, "ph1")
        XCTAssertGreaterThan(keyword, 0)
        XCTAssertEqual(shelf, "s1")
        XCTAssertEqual(response, "user-1")
    }

    func testFieldArgumentsOfEveryShape() async throws {
        let literals = try await client.queries.shelfItems().shelf.items
        XCTAssertEqual(literals, ["tags=[a, b]", "kind=x__y", "filter={n=3, label=L}", "limit=5"])
        let r = try await client.queries.shelfItemsVars(tags: ["t"], kind: .v1, filter: InnerInput(n: 1, label: "f"), limit: 7).shelf.items
        XCTAssertEqual([r[0], r[1], r[3]], ["tags=[t]", "kind=v1", "limit=7"])
        let defaults = try await client.queries.shelfItemsDefaults().shelf.items
        XCTAssertEqual(defaults.last, "limit=2")
    }

    func testLiteralArgumentsOfEveryKind() async throws {
        let l = try await client.queries.literalLists().echoArgs
        XCTAssertEqual(l.a, [1, 2, 3])
        XCTAssertEqual(l.b, [1, nil])
        XCTAssertEqual(l.c, [[1], [2, 3]])
        XCTAssertEqual(l.e, [.a, .xY])
        XCTAssertEqual(l.f, [nil, .v1])
        XCTAssertEqual(l.g, [.snakeCase2])
        XCTAssertEqual(l.one, .only)

        let i = try await client.queries.literalInput().echoInput
        XCTAssertEqual(i.a, [4])
        XCTAssertEqual(i.b, [nil, 5])
        XCTAssertEqual(i.c, [[6]])

        let s = try await client.queries.literalScalars().echoEverything
        XCTAssertEqual([s.i, s.neg, s.big], [5, -3, 9])
        XCTAssertEqual([s.f, s.exp], [2.5, 100.0])
        XCTAssertEqual([s.b, s.bf], [false, true])
        XCTAssertEqual([s.s, s.id], ["lit", "q"])
        XCTAssertEqual(s.e, .v1)
        XCTAssertEqual(s.inner?.label, "L")
        XCTAssertNil(s.nothing)
        XCTAssertNil(s.emptyObj?.n)

        let m = try await client.queries.literalsMixed(a: [8], one: .only).echoArgs
        XCTAssertEqual(m.a, [8])
        XCTAssertEqual(m.e, [.a, .b2])
    }
}
