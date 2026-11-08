import Foundation
import XCTest
@testable import GraphLinkGenerated

private func collect<T>(_ stream: AsyncThrowingStream<T, Error>, count: Int, timeout: TimeInterval = 10) async throws -> [T] {
    try await withThrowingTaskGroup(of: [T].self) { group in
        group.addTask {
            var events: [T] = []
            for try await value in stream {
                events.append(value)
                if events.count >= count { break }
            }
            return events
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private func typeName(_ value: Any?) -> String {
    guard let value = value else { return "nil" }
    return String(describing: type(of: value))
}

private func names(_ values: [Any?]) -> [String] { values.map(typeName) }

private func get(_ value: Any?, _ key: String) -> Any? {
    guard let object = value as? [String: Any?] else { return nil }
    return object[key] ?? nil
}

private func at(_ value: Any?, _ index: Int) -> Any? {
    guard let list = value as? [Any?] else { return nil }
    return list[index]
}

private func decoded(_ value: Any, _ name: String) -> Any? {
    for child in Mirror(reflecting: value).children where child.label == name {
        let inner = Mirror(reflecting: child.value)
        return inner.displayStyle == .optional ? inner.children.first?.value : child.value
    }
    return nil
}

final class PolymorphicExtrasTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    // ── nested lists of polymorphic types ───────────────────────────────────

    func test_listsOfListsOfUnionsAndInterfaces() async throws {
        let grid = try await client.queries.grid().grid
        XCTAssertEqual(grid.cells.map { names(($0 ?? []) as [Any?]) }, [["Photo", "nil"], ["Video"], []])
        XCTAssertEqual(grid.rows.map { names($0 as [Any?]) }, [["Article", "Comment"], ["Article"]])
        XCTAssertEqual(names((grid.maybe![0] ?? []) as [Any?]), ["Photo", "Document"])
    }

    func test_emptyAndNullListsStayAsTheyAre() async throws {
        let grid = try await client.queries.grid(empty: true).grid
        XCTAssertTrue(grid.cells.isEmpty)
        XCTAssertTrue(grid.rows.isEmpty)
        XCTAssertNil(grid.maybe)
    }

    func test_aProjectedSelectionOfNestedLists() async throws {
        let grid = try await client.queries.gridProjected().grid.toJson()
        let cells = grid["cells"] as Any?
        XCTAssertEqual(get(at(at(cells, 0), 0), "width") as? Int, 640)
        XCTAssertNil(at(at(cells, 0), 1))
        XCTAssertEqual(get(at(at(cells, 1), 0), "seconds") as? Int, 30)
        XCTAssertEqual((at(cells, 2) as? [Any?])?.count, 0)
        let rows = at(grid["rows"] as Any?, 0)
        XCTAssertEqual(get(at(rows, 0), "id") as? String, "a1")
        XCTAssertEqual(get(at(rows, 0), "title") as? String, "Hello")
        XCTAssertEqual(get(at(rows, 1), "text") as? String, "Nice")
        let maybe = at(grid["maybe"] as Any?, 0)
        XCTAssertEqual(get(at(maybe, 0), "url") as? String, "http://cdn/1.png")
        XCTAssertEqual(get(at(maybe, 1), "id") as? String, "d1")
    }

    // ── custom scalars inside polymorphic types ─────────────────────────────

    func test_aListOfAUnionWithScalarFields() async throws {
        let moments = try await client.queries.moments().moments
        let stamp = try XCTUnwrap(moments[0] as? Stamp)
        XCTAssertEqual(stamp.at, "2026-01-02T03:04:05Z")
        XCTAssertEqual(stamp.big, 4294967296)
        let span = try XCTUnwrap(moments[1] as? Span)
        XCTAssertEqual(span.until, "2026-02-04")
        XCTAssertEqual(span.opaque, "opaque:o-9")
        XCTAssertEqual(span.dts, ["2026-03-04T05:06:07Z"])
    }

    func test_aListOfAnInterfaceWithScalarFields() async throws {
        let timed = try await client.queries.timed().timed
        XCTAssertEqual(names(timed as [Any?]), ["Span", "Stamp"])
        XCTAssertEqual((timed[0] as? Span)?.opaque, "opaque:o-9")
        XCTAssertEqual((timed[1] as? Stamp)?.big, 4294967296)
    }

    func test_aProjectedUnionKeepsTheScalarsItSelects() async throws {
        let moments = try await client.queries.momentsProjected().moments
        XCTAssertEqual(decoded(moments[0], "at") as? String, "2026-01-02T03:04:05Z")
        XCTAssertEqual(decoded(moments[0], "big") as? Int, 4294967296)
        XCTAssertEqual(decoded(moments[1], "opaque") as? String, "opaque:o-9")
        XCTAssertEqual(decoded(moments[1], "until") as? String, "2026-02-04")
    }

    func test_anInterfaceSelectionSharesTheInterfaceScalar() async throws {
        let timed = try await client.queries.timedProjected().timed
        XCTAssertEqual(timed.map { decoded($0, "at") as? String }, ["2026-02-03T04:05:06Z", "2026-01-02T03:04:05Z"])
        XCTAssertEqual(decoded(timed[0], "opaque") as? String, "opaque:o-9")
        XCTAssertEqual(decoded(timed[1], "big") as? Int, 4294967296)
    }

    // ── a union member that points back at its union ────────────────────────

    func test_aChainThreeLevelsDeep() async throws {
        let response = try await client.queries.chainDeep(id: "l1")
        let chain = try XCTUnwrap(response.chain).toJson() as [String: Any?]
        XCTAssertEqual(chain["id"] as? String, "l1")
        XCTAssertEqual(get(chain["next"] as Any?, "id") as? String, "l2")
        let last = get(get(chain["next"] as Any?, "next"), "id") as? String
        XCTAssertEqual(last, "e1")
        XCTAssertEqual(get(get(chain["next"] as Any?, "next"), "reason") as? String, "done")
    }

    func test_theEndOfTheChainDirectlyAndAnUnknownId() async throws {
        let endResponse = try await client.queries.chainDeep(id: "e1")
        let end = try XCTUnwrap(endResponse.chain).toJson()
        XCTAssertEqual(end["reason"] as? String, "done")
        let unknown = try await client.queries.chainDeep(id: "nope").chain
        XCTAssertNil(unknown)
    }

    func test_theAllFieldsSelectionStopsAfterOneLevel() async throws {
        let response = try await client.queries.chain(id: "l1")
        let chain = try XCTUnwrap(response.chain).toJson()
        XCTAssertEqual(chain["id"] as? String, "l1")
        XCTAssertEqual(get(chain["next"] as Any?, "id") as? String, "l2")
    }

    // ── lists of unions and interfaces in every operation kind ──────────────

    private func cachedVideoSeconds() async throws -> Int? {
        (try await client.queries.cachedAttachments().cachedAttachments[1] as? Video)?.seconds
    }

    func test_aCachedListIsServedOnceAndFetchedAgainAfterItsTagIsEvicted() async throws {
        let first = try await client.queries.cachedAttachments().cachedAttachments
        XCTAssertEqual(names(first as [Any?]), ["Photo", "Video", "Document"])
        let before = try await cachedVideoSeconds()
        let again = try await cachedVideoSeconds()
        XCTAssertEqual(again, before)
        _ = try await client.mutations.evictAttachments()
        let after = try await cachedVideoSeconds()
        XCTAssertNotEqual(after, before)
    }

    func test_anErrorOnAListOfUnionsThrowsAndAGoodCallStillWorks() async throws {
        do {
            _ = try await client.queries.failingAttachments(fail: true)
            XCTFail("expected an error")
        } catch {}
        let ok = try await client.queries.failingAttachments(fail: false).failingAttachments
        XCTAssertEqual(ok.count, 3)
    }

    func test_aMutationReturningAListOfUnions() async throws {
        let five = try await client.mutations.bulkAttachments(n: 5).bulkAttachments
        XCTAssertEqual(names(five as [Any?]), ["Photo", "Video", "Document", "Photo", "Video"])
        let none = try await client.mutations.bulkAttachments(n: 0).bulkAttachments
        XCTAssertTrue(none.isEmpty)
    }

    func test_aMutationReturningAListOfAnInterface() async throws {
        let entities = try await client.mutations.bulkEntities().bulkEntities
        XCTAssertEqual(names(entities as [Any?]), ["Article", "Comment", "Article"])
    }

    func test_aSubscriptionEmittingListsOfUnions() async throws {
        let batches = try await collect(client.subscriptions.attachmentsBatch(), count: 2)
        XCTAssertEqual(names(batches[0].attachmentsBatch as [Any?]), ["Photo", "Video", "Document"])
        XCTAssertEqual(names(batches[1].attachmentsBatch as [Any?]), ["Document"])
    }

    func test_aSubscriptionEmittingAListOfAnInterface() async throws {
        let batches = try await collect(client.subscriptions.entityBatch(), count: 1)
        XCTAssertEqual(names(batches[0].entityBatch as [Any?]), ["Article", "Comment"])
    }

    // ── @oneOf inputs with richer members ───────────────────────────────────

    private func pick(_ pick: Pick) async throws -> String {
        try await client.queries.describePick(pick: pick).describePick
    }

    func test_oneOfWithAnInputObject() async throws {
        let value = try await pick(Pick(inner: InnerInput(n: 5, label: "x", tags: ["t"])))
        XCTAssertEqual(value, "{inner={label=x, n=5, tags=[t]}}")
    }

    func test_oneOfWithAnEnum() async throws {
        let value = try await pick(Pick(status: .suspended))
        XCTAssertEqual(value, "{status=SUSPENDED}")
    }

    func test_oneOfWithAListIncludingAnEmptyOne() async throws {
        let two = try await pick(Pick(ids: [1, 2]))
        XCTAssertEqual(two, "{ids=[1, 2]}")
        let none = try await pick(Pick(ids: []))
        XCTAssertEqual(none, "{ids=[]}")
    }

    func test_oneOfWithAnotherOneOf() async throws {
        let value = try await pick(Pick(pet: Pet(cat: "Tom")))
        XCTAssertEqual(value, "{pet={cat=Tom}}")
    }

    func test_oneOfNestedInItself() async throws {
        let value = try await pick(Pick(child: Pick(child: Pick(pet: Pet(dog: 3)))))
        XCTAssertEqual(value, "{child={child={pet={dog=3}}}}")
    }

    func test_aListOfOneOfInputsInsideARegularInput() async throws {
        let pets = [Pet(cat: "a"), Pet(dog: 2)]
        let both = try await client.queries.describeBasket(basket: Basket(pets: pets, lead: Pet(dog: 3))).describeBasket
        XCTAssertEqual(both, "{lead={dog=3}, pets=[{cat=a}, {dog=2}]}")
        let noLead = try await client.queries.describeBasket(basket: Basket(pets: pets)).describeBasket
        XCTAssertEqual(noLead, "{pets=[{cat=a}, {dog=2}]}")
        let empty = try await client.queries.describeBasket(basket: Basket(pets: [])).describeBasket
        XCTAssertEqual(empty, "{pets=[]}")
    }
}
