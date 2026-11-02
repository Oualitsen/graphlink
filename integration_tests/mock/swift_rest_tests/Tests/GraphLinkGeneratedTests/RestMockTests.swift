import XCTest
@testable import GraphLinkGenerated

private let product: [String: Any] = ["id": "p1", "name": "Pen", "price": 2.5, "status": "ACTIVE", "tags": ["a", "b"]]

class RestMockCase: XCTestCase {
    var rest: MockRest!
    var client: GraphLinkClient!
    override func setUp() {
        rest = MockRest()
        client = clientFor(rest)
    }
}

final class RequestsTests: RestMockCase {
    func test_pathVariableEncodedAndEnumQueryValueSent() async throws {
        rest.on("GET", "/products/a%20b", json: product)
        let result = try await client.queries.product(id: "a b", status: .archived)
        XCTAssertEqual(result?.name, "Pen")
        XCTAssertEqual(rest.last.method, "GET")
        XCTAssertEqual(queryString(rest.last), "status=ARCHIVED")
        XCTAssertEqual(rest.last.headers["Accept"], "application/json")
        XCTAssertNil(rest.last.body)
        XCTAssertNil(rest.last.headers["Content-Type"])
    }

    func test_defaultsListsAndSpreads() async throws {
        rest.on("GET", "/products", json: [product])
        _ = try await client.queries.products(filter: Filter(tag: "x", minPrice: 3), auth: Auth(token: "t", requestId: "r1"), ids: ["1", "2"])
        XCTAssertEqual(queryString(rest.last), "tag=x&minPrice=3.0&page=1&ids=1&ids=2")
        XCTAssertEqual(rest.last.headers["token"], "t")
        XCTAssertEqual(rest.last.headers["X-Request-Id"], "r1")
    }

    func test_nullOptionalsAreOmitted() async throws {
        rest.on("GET", "/products", json: [])
        _ = try await client.queries.products()
        XCTAssertEqual(queryString(rest.last), "page=1")
    }

    func test_flatObjectsInAListUseIndexedKeys() async throws {
        rest.on("GET", "/products/search", json: ["data": ["total": 1, "items": [product]]])
        let page = try await client.queries.search(q: "pen", groups: [Group(name: "g", ids: [1, 2]), Group(name: "h")], tags: ["x", "y"])
        XCTAssertEqual(
            queryString(rest.last).split(separator: "&").map(String.init).sorted(),
            "q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y".split(separator: "&").map(String.init).sorted()
        )
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items[0].id, "p1")
    }

    func test_jsonBodyIsTheArgumentItself() async throws {
        rest.on("POST", "/products", status: 201, json: product)
        let created = try await client.mutations.createProduct(input: ProductIn(name: "Pen", price: 2.5))
        XCTAssertEqual(created.id, "p1")
        let decoded = try JSONSerialization.jsonObject(with: Data(rest.bodies[0].utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["name"] as? String, "Pen")
        XCTAssertEqual(decoded?["price"] as? Double, 2.5)
        XCTAssertEqual(rest.last.headers["Content-Type"], "application/json")
    }

    func test_formBodyCarriesOnlyNonNullFields() async throws {
        rest.on("POST", "/products/p1/rename", json: product)
        _ = try await client.mutations.rename(id: "p1", name: "New")
        guard case .form(let fields)? = rest.last.body else { return XCTFail("not a form body") }
        XCTAssertEqual(fields, [RestEntry("name", "New")])
        XCTAssertEqual(rest.last.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func test_multipartCarriesTextAndFileParts() async throws {
        rest.on("POST", "/products/p1/gallery", json: product)
        _ = try await client.mutations.gallery(id: "p1", title: "T", files: [textUpload("1", filename: "a.png"), textUpload("2", filename: "b.png")])
        guard case .multipart(let parts)? = rest.last.body else { return XCTFail("not multipart") }
        XCTAssertEqual(parts.map(\.name), ["title", "files", "files"])
        XCTAssertEqual(parts[0].value, "T")
        XCTAssertEqual(parts[2].file?.filename, "b.png")
        XCTAssertNil(rest.last.headers["Content-Type"])
    }

    func test_rawBodyCarriesTheUploadWithItsMimeType() async throws {
        rest.on("PUT", "/products/p1/avatar", status: 204)
        try await client.mutations.avatar(id: "p1", file: textUpload("bytes", mimeType: "image/png"))
        XCTAssertEqual(rest.bodies[0], "bytes")
        XCTAssertEqual(rest.last.headers["Content-Type"], "image/png")
    }
}

final class ResponsesTests: RestMockCase {
    func test_voidAcceptsAny2xxAndIgnoresTheBody() async throws {
        rest.on("DELETE", "/products/p1", text: "whatever")
        try await client.mutations.deleteProduct(id: "p1")
        XCTAssertEqual(rest.last.method, "DELETE")
    }

    func test_nullableResultWithEmptyBodyIsNull() async throws {
        rest.on("GET", "/products/p1", status: 204)
        let value = try await client.queries.product(id: "p1")
        XCTAssertNil(value)
    }

    func test_nonNullResultWithEmptyBodyIsAnError() async throws {
        rest.on("GET", "/products/count")
        let failure = await capture { try await self.client.queries.count() }
        XCTAssertTrue(String(describing: failure as Any).contains("Empty REST response"))
    }

    func test_non2xxRaisesRestError() async throws {
        rest.on("GET", "/products/p1", status: 404, text: "nope", headers: ["x-a": "b"])
        let failure = await capture { try await self.client.queries.product(id: "p1") }
        let error = try XCTUnwrap(failure as? RestError)
        XCTAssertEqual([error.status], [404])
        XCTAssertEqual(error.body, "nope")
        XCTAssertEqual(error.headers["x-a"], "b")
    }

    func test_textAndScalarResults() async throws {
        rest.on("GET", "/products/p1/note", text: "hello")
        let note = try await client.queries.note(id: "p1")
        XCTAssertEqual(note, "hello")
        rest.on("GET", "/products/count", json: 7)
        let count = try await client.queries.count()
        XCTAssertEqual(count, 7)
    }
}

final class CacheMockTests: RestMockCase {
    private func gets() -> Int { rest.calls.filter { $0.method == "GET" }.count }

    func test_cachedGetQueryHitsTheAdapterOnce() async throws {
        rest.on("GET", "/products/cached/p1", json: product)
        _ = try await client.queries.cached(id: "p1")
        _ = try await client.queries.cached(id: "p1")
        XCTAssertEqual(rest.calls.count, 1)
        rest.on("GET", "/products/cached/p2", json: product)
        _ = try await client.queries.cached(id: "p2")
        XCTAssertEqual(rest.calls.count, 2)
    }

    func test_mutationInvalidatesTheTagAfterA2xx() async throws {
        rest.on("GET", "/products/cached/p1", json: product)
        rest.on("PUT", "/products/cached/p1", json: product)
        _ = try await client.queries.cached(id: "p1")
        _ = try await client.mutations.updateCached(id: "p1", input: ProductIn(name: "x"))
        _ = try await client.queries.cached(id: "p1")
        XCTAssertEqual(gets(), 2)
    }

    func test_failedMutationDoesNotInvalidate() async throws {
        rest.on("GET", "/products/cached/p1", json: product)
        rest.on("PUT", "/products/cached/p1", status: 500, text: "boom")
        _ = try await client.queries.cached(id: "p1")
        let failure = await capture { try await self.client.mutations.updateCached(id: "p1", input: ProductIn(name: "x")) }
        XCTAssertNotNil(failure as? RestError)
        _ = try await client.queries.cached(id: "p1")
        XCTAssertEqual(gets(), 1)
    }

    func test_staleIfOfflineServesStaleDataOnATransportFailureOnly() async throws {
        rest.on("GET", "/products/offline/p1", json: product)
        _ = try await client.queries.cachedOffline(id: "p1")
        try await Task.sleep(nanoseconds: 1_100_000_000)
        rest.failTransport = true
        let stale = try await client.queries.cachedOffline(id: "p1")
        XCTAssertEqual(stale?.id, "p1")
        rest.failTransport = false
        rest.on("GET", "/products/offline/p1", status: 500, text: "down")
        let failure = await capture { try await self.client.queries.cachedOffline(id: "p1") }
        XCTAssertNotNil(failure as? RestError)
    }
}

final class MixedAndDownloadsTests: RestMockCase {
    func test_graphqlAndRestShareOneClient() async throws {
        rest.on("GET", "/products/count", json: 3)
        let ping = try await client.queries.ping()
        XCTAssertEqual(ping.ping, "pong")
        let count = try await client.queries.count()
        XCTAssertEqual(count, 3)
    }

    func test_downloadMetadataComesFromTheResponse() async throws {
        rest.on("GET", "/products/p1/export", text: "abcdef", headers: [
            "Content-Type": "text/csv", "Content-Length": "6", "Content-Disposition": "attachment; filename=\"p 1.csv\"",
        ])
        let received = Collector<Int>()
        let download = try await client.queries.export(id: "p1", onReceiveProgress: { received.add($0 * 100 + $1) })
        XCTAssertEqual(download.filename, "p 1.csv")
        XCTAssertEqual(download.contentType, "text/csv")
        XCTAssertEqual(download.length, 6)
        XCTAssertEqual(rest.last.headers["Accept"], "*/*")
        let data = try await download.data()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "abcdef")
        XCTAssertEqual(received.all.last, 606)
    }

    func test_rfc5987FilenameIsDecoded() async throws {
        rest.on("GET", "/products/p1/export", text: "x", headers: ["Content-Disposition": "attachment; filename*=UTF-8''p%201%C3%A9.csv"])
        let download = try await client.queries.export(id: "p1")
        XCTAssertEqual(download.filename, "p 1é.csv")
    }

    func test_nullableDownloadNullOn204AndNonNullIsAnError() async throws {
        rest.on("GET", "/products/p1/maybe", status: 204)
        let maybe = try await client.queries.maybeExport(id: "p1")
        XCTAssertNil(maybe)
        rest.on("GET", "/products/p1/export", status: 204)
        let failure = await capture { try await self.client.queries.export(id: "p1") }
        XCTAssertTrue(String(describing: failure as Any).contains("Empty REST response"))
    }

    func test_non2xxDownloadRaisesRestError() async throws {
        rest.on("GET", "/products/p1/export", status: 500, text: "x")
        let failure = await capture { try await self.client.queries.export(id: "p1") }
        XCTAssertNotNil(failure as? RestError)
    }
}
