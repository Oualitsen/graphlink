import XCTest
@testable import GraphLinkGenerated

final class HeaderArgumentsTests: RestCase {
    func test_scalarHeaderAndSpreadInput() async throws {
        let e = try await client.queries.eHeaders(tenant: "t-1", trace: Trace(traceId: "tr", spanId: "sp"))
        XCTAssertEqual(header(e, "X-Tenant"), "t-1")
        XCTAssertEqual(header(e, "X-Trace-Id"), "tr")
        XCTAssertEqual(header(e, "X-Span-Id"), "sp")
    }

    func test_nullHeaderFieldAndArgumentAreNotSent() async throws {
        let e = try await client.queries.eHeaders(tenant: "t", trace: Trace(traceId: "tr"))
        XCTAssertNil(header(e, "X-Span-Id"))
        XCTAssertNil(header(e, "X-Opt"))
        XCTAssertNil(header(e, "X-Roles"))
    }

    func test_listHeaderIsJoinedWithCommas() async throws {
        let v31 = try await client.queries.eHeaders(tenant: "t", roles: ["admin", "ops"])
        XCTAssertEqual(header(v31, "X-Roles"), "admin,ops")
    }

    func test_acceptDefaultAndOverrideAndNoContentTypeOnGet() async throws {
        let e = try await client.queries.eAccept()
        XCTAssertEqual(header(e, "accept"), "application/json")
        XCTAssertNil(e.contentType)
        let v32 = try await client.queries.eAcceptOverride()
        XCTAssertEqual(header(v32, "accept"), "application/vnd.test+json")
    }
}

final class AdapterHeadersTests: RestCase {
    func test_providerIsConsultedForEveryRequest() async throws {
        let calls = Collector<Int>()
        let c = newClient(headers: {
            calls.add(1)
            return ["X-Provider": "call-\(calls.all.count)"]
        })
        let v33 = try await c.queries.eAccept()
        XCTAssertEqual(header(v33, "X-Provider"), "call-1")
        let v34 = try await c.queries.eAccept()
        XCTAssertEqual(header(v34, "X-Provider"), "call-2")
    }

    func test_argumentHeaderWinsOverProvider() async throws {
        let c = newClient(headers: { ["X-Tenant": "from-provider", "X-Other": "kept"] })
        let e = try await c.queries.eHeaders(tenant: "from-arg")
        XCTAssertEqual(header(e, "X-Tenant"), "from-arg")
        XCTAssertEqual(header(e, "X-Other"), "kept")
    }

    func test_authThroughProviderAnd401Without() async throws {
        let failure = await capture { try await self.client.queries.authCheck() }
        let error = try XCTUnwrap(failure as? RestError)
        XCTAssertEqual(error.status, 401)
        XCTAssertEqual(error.headers["www-authenticate"], "Bearer")
        let c = newClient(headers: { ["Authorization": "Bearer secret"] })
        let who = try await c.queries.authCheck(tenant: "acme")
        XCTAssertEqual([who.user, who.tenant], ["ann", "acme"])
    }
}
