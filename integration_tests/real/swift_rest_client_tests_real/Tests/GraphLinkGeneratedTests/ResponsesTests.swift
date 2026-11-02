import XCTest
@testable import GraphLinkGenerated

final class StatusHandlingTests: RestCase {
    func test_200And201DecodeTheBody() async throws {
        let v35 = try await client.queries.status(code: 200)?.name
        XCTAssertEqual(v35, "Pen")
        let v36 = try await client.queries.status(code: 201)?.id
        XCTAssertEqual(v36, "p1")
    }

    func test_204IsNullWhenNullableAndAnErrorWhenNot() async throws {
        let value = try await client.queries.status(code: 204)
        XCTAssertNil(value)
        let failure = await capture { try await self.client.queries.statusNonNull(code: 204) }
        XCTAssertTrue(String(describing: failure as Any).contains("Empty REST response"))
    }

    func test_errorStatusesRaiseRestError() async throws {
        for code in [400, 401, 403, 404, 409, 422, 500, 502, 503] {
            let failure = await capture { try await self.client.queries.status(code: code) }
            let error = try XCTUnwrap(failure as? RestError, "code \(code)")
            XCTAssertEqual(error.status, code)
            XCTAssertTrue(error.body.contains("status \(code)"))
            XCTAssertEqual(error.headers["x-reason"], "reason-\(code)")
        }
    }

    func test_restErrorPrintsItsStatus() async throws {
        let failure = await capture { try await self.client.queries.status(code: 418) }
        XCTAssertTrue(String(describing: failure as Any).contains("418"))
    }

    func test_failedCallDoesNotPoisonTheNextOne() async throws {
        _ = await capture { try await self.client.queries.status(code: 500) }
        let v37 = try await client.queries.status(code: 200)?.id
        XCTAssertEqual(v37, "p1")
    }
}

final class EmptyBodiesTests: RestCase {
    func test_empty200NullOrError() async throws {
        let blank = try await client.queries.blank()
        XCTAssertNil(blank)
        let failure = await capture { try await self.client.queries.blankNonNull() }
        XCTAssertTrue(String(describing: failure as Any).contains("Empty REST response"))
    }

    func test_204AndJsonNullAreNullWhenNullable() async throws {
        let a = try await client.queries.noContent()
        let b = try await client.queries.textOptional()
        let c = try await client.queries.jsonNull()
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertNil(c)
    }
}

final class ValueKindsTests: RestCase {
    func test_scalarsAndText() async throws {
        let v38 = try await client.queries.count()
        XCTAssertEqual(v38, 7)
        let v39 = try await client.queries.flag()
        XCTAssertEqual(v39, true)
        let v40 = try await client.queries.text()
        XCTAssertEqual(v40, "héllo ✓")
    }

    func test_responsePathSelectsANestedValue() async throws {
        let v41 = try await client.queries.deep()
        XCTAssertEqual(v41, [1, 2, 3])
        let v42 = try await client.queries.wrapped().map(\.id)
        XCTAssertEqual(v42, ["p1", "p2"])
    }

    func test_nonAsciiJsonDecodes() async throws {
        let p = try await client.queries.unicode()
        XCTAssertEqual(p.name, "é漢😀 \"quoted\"")
        XCTAssertEqual(p.tags, ["ß"])
    }

    func test_unknownKeysIgnoredAndNullListStaysNull() async throws {
        let p = try await client.queries.extraKeys()
        XCTAssertEqual(p.id, "x")
        XCTAssertNil(p.tags)
    }


    func test_nestedTypesEnumsAndCyclesDecode() async throws {
        let v43 = try await client.queries.product(id: "p1")
        let p = try XCTUnwrap(v43)
        XCTAssertEqual(p.status, .active)
        XCTAssertEqual(p.related?.count, 1)
        XCTAssertEqual(p.related?.first?.name, "Book")
        XCTAssertNil(p.related?.first?.related)
    }
}

final class PolymorphismTests: RestCase {
    func test_interfaceDecodesThroughTheDiscriminator() async throws {
        let pets = try await client.queries.pets()
        XCTAssertEqual((pets[0] as? Dog)?.barks, true)
        XCTAssertEqual((pets[1] as? Cat)?.lives, 9)
    }

    func test_singleInterfaceValue() async throws {
        let v44 = try await client.queries.pet(id: "c1")
        let pet = try XCTUnwrap(v44)
        XCTAssertTrue(pet is Cat)
        XCTAssertEqual(pet.name, "Tom")
    }


    func test_unionDecodesThroughItsDiscriminatorMap() async throws {
        let hits = try await client.queries.hits()
        XCTAssertTrue(hits[0] is Product)
        XCTAssertTrue(hits[1] is Owner)
    }
}

final class MixedClientTests: RestCase {
    func test_graphqlAndRestShareOneClient() async throws {
        let v45 = try await client.queries.getCount().getCount
        XCTAssertEqual(v45, 19)
        let v46 = try await client.queries.count()
        XCTAssertEqual(v46, 7)
    }

    func test_createFactoryBuildsBothAdapters() async throws {
        let c = GraphLinkClient.create(url: URL(string: serverUrl + "/graphql")!, restBaseUrl: URL(string: serverUrl)!)
        let v47 = try await c.queries.count()
        XCTAssertEqual(v47, 7)
        let v48 = try await c.queries.getCount().getCount
        XCTAssertEqual(v48, 19)
    }
}

final class TransportEdgeCasesTests: RestCase {
    func test_gzipIsDecompressed() async throws {
        let v49 = try await client.queries.gzipped().map(\.id)
        XCTAssertEqual(v49, ["p1", "p2"])
    }

    func test_redirectIsFollowed() async throws {
        let v50 = try await client.queries.redirected()
        XCTAssertEqual(v50, 7)
    }

    func test_largeJsonResponseDecodesCompletely() async throws {
        let items = try await client.queries.big(n: 50000)
        XCTAssertEqual(items.count, 50000)
        XCTAssertEqual(items.last?.name, "big-49999")
    }

    func test_invalidJsonIsAFormatErrorNotARestError() async throws {
        let failure = await capture { try await self.client.queries.invalidJson() }
        XCTAssertNotNil(failure)
        XCTAssertNil(failure as? RestError)
    }

    func test_nonJsonErrorBodyIsKeptAsText() async throws {
        let failure = await capture { try await self.client.queries.htmlError() }
        let error = try XCTUnwrap(failure as? RestError)
        XCTAssertEqual(error.status, 500)
        XCTAssertTrue(error.body.contains("Internal Server Error"))
        XCTAssertTrue(error.headers["content-type"]?.hasPrefix("text/html") ?? false)
    }
}
