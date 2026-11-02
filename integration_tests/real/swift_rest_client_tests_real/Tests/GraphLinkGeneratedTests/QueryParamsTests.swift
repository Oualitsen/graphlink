import XCTest
@testable import GraphLinkGenerated

final class ScalarsAndPathsTests: RestCase {
    func test_everyScalarKindIsAQueryValue() async throws {
        let e = try await client.queries.eScalars(id: "x1", s: "hello", i: 3, f: 2.5, b: true, st: .archived, renamed: "r")
        XCTAssertEqual(e.method, "GET")
        XCTAssertEqual(e.path, "/echo/scalars/x1")
        XCTAssertEqual(queryPairs(e), ["s=hello", "i=3", "f=2.5", "b=true", "st=ARCHIVED", "dflt=5", "x-ren=r"])
        XCTAssertEqual(e.bodySize, 0)
        XCTAssertNil(e.contentType)
        XCTAssertEqual(header(e, "accept"), "application/json")
    }

    func test_omittedOptionalAbsentDefaultSentExplicitReplaces() async throws {
        let v67 = try await client.queries.eScalars(id: "x1")
        XCTAssertEqual(queryPairs(v67), ["dflt=5"])
        let v68 = try await client.queries.eScalars(id: "x1", dflt: 9)
        XCTAssertEqual(queryPairs(v68), ["dflt=9"])
    }

    func test_falseAndZeroAreValuesNotOmissions() async throws {
        let e = try await client.queries.eScalars(id: "x1", s: "", i: 0, b: false)
        XCTAssertEqual(queryPairs(e), ["s=", "i=0", "b=false", "dflt=5"])
    }

    func test_reservedAndNonAsciiCharactersSurvive() async throws {
        let segment = "a b/c?d#é+%"
        let value = "a&b=c d+e/é\"%25"
        let e = try await client.queries.eSpecial(segment: segment, q: value, other: "ü")
        XCTAssertEqual(e.path, "/echo/special/\(restEncode(segment))/tail")
        XCTAssertEqual(queryValue(e, "q"), value)
        XCTAssertEqual(queryValue(e, "other"), "ü")
    }

    func test_emptyStringIsNotDropped() async throws {
        let e = try await client.queries.eSpecial(segment: "seg", q: "")
        XCTAssertEqual(queryValue(e, "q"), "")
    }

    func test_deleteCarriesArgumentsInTheQuery() async throws {
        let e = try await client.queries.eDeleteQuery(id: "d1", force: true)
        XCTAssertEqual([e.method, e.path], ["DELETE", "/echo/delete/d1"])
        XCTAssertEqual(queryPairs(e), ["force=true"])
        XCTAssertEqual(e.bodySize, 0)
    }
}

final class ListsTests: RestCase {
    func test_scalarListsRepeatOrJoinAndEmptySendsNothing() async throws {
        let e = try await client.queries.eLists(tags: ["a", "b c"], ids: [1, 2, 3], empty: [])
        XCTAssertEqual(queryPairs(e), Variant.list("tags", ["a", "b c"]) + Variant.list("ids", ["1", "2", "3"]))
        XCTAssertNil(queryValue(e, "empty"))
    }

    func test_matrixUsesIndexedKeys() async throws {
        let e = try await client.queries.eLists(matrix: [[1, 2], [3]])
        XCTAssertEqual(queryPairs(e), [
            "\(Variant.key("matrix", ["0", "0"]))=1",
            "\(Variant.key("matrix", ["0", "1"]))=2",
            "\(Variant.key("matrix", ["1", "0"]))=3",
        ])
    }

    func test_listOfObjectsUsesIndexedKeys() async throws {
        let e = try await client.queries.eLists(rows: [Row(name: "r0", ids: [1, 2]), Row(name: "r1")])
        let expected = ["\(Variant.key("rows", ["0", "name"]))=r0"]
            + Variant.list(Variant.key("rows", ["0", "ids"]), ["1", "2"])
            + ["\(Variant.key("rows", ["1", "name"]))=r1"]
        XCTAssertEqual(queryPairs(e).sorted(), expected.sorted())
    }

    func test_itemsWithReservedCharactersRoundTrip() async throws {
        let e = try await client.queries.eLists(tags: ["a&b", "c=d", "e f", "é"])
        if Variant.comma {
            XCTAssertEqual(queryValue(e, "tags"), "a&b,c=d,e f,é")
        } else {
            XCTAssertEqual(e.query.filter { $0.name == "tags" }.map(\.value).joined(separator: "|"), "a&b|c=d|e f|é")
        }
    }
}

final class ObjectsTests: RestCase {
    func test_inputIsSpreadByDefault() async throws {
        let e = try await client.queries.eObjects(filter: Filter(tag: "x", minPrice: 3, status: .active))
        XCTAssertEqual(queryPairs(e), ["tag=x", "minPrice=3.0", "status=ACTIVE"])
    }

    func test_spreadInputWithUnsetFieldsSendsOnlySetOnes() async throws {
        let v69 = try await client.queries.eObjects(filter: Filter(tag: "x"))
        XCTAssertEqual(queryPairs(v69), ["tag=x"])
    }

    func test_flatNestsWithTheConfiguredSeparator() async throws {
        let meta = Meta(name: "m", tags: ["t1", "t2"], address: Address(city: "Oran", street: "Rue 1", geo: Geo(lat: 35.7, lng: -0.6)))
        let e = try await client.queries.eObjects(meta: meta)
        let expected = [
            "\(Variant.key("meta", ["address", "city"]))=Oran",
            "\(Variant.key("meta", ["address", "geo", "lat"]))=35.7",
            "\(Variant.key("meta", ["address", "geo", "lng"]))=-0.6",
            "\(Variant.key("meta", ["address", "street"]))=Rue 1",
            "\(Variant.key("meta", ["name"]))=m",
        ] + Variant.list(Variant.key("meta", ["tags"]), ["t1", "t2"])
        XCTAssertEqual(queryPairs(e).sorted(), expected.sorted())
    }

    func test_jsonEncodingSendsOneKeyHoldingJsonText() async throws {
        let e = try await client.queries.eObjects(asJson: Meta(name: "m", tags: ["a"], address: Address(city: "c")))
        XCTAssertEqual(e.query.map(\.name), ["j"])
        let json = try JSONSerialization.jsonObject(with: Data((queryValue(e, "j") ?? "").utf8)) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "m")
        XCTAssertEqual(json?["tags"] as? [String], ["a"])
        XCTAssertEqual((json?["address"] as? [String: Any])?["city"] as? String, "c")
    }

    func test_severalRolesKeepTheirOwnKeys() async throws {
        let e = try await client.queries.eObjects(filter: Filter(tag: "x"), meta: Meta(name: "m"), asJson: Meta(name: "j"))
        XCTAssertEqual(Set(e.query.map(\.name)), ["tag", Variant.key("meta", ["name"]), "j"])
    }
}
