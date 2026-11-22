import Foundation
import XCTest
@testable import GraphLinkGenerated

final class RestErrorsTests: XCTestCase {
    let client = GraphLinkClient(
        adapter: DefaultGraphLinkURLSessionAdapter(url: URL(string: "http://127.0.0.1:9930/graphql")!).execute,
        restAdapter: DefaultGraphLinkRestAdapter(baseUrl: "http://127.0.0.1:9930").execute)

    func thrownBy(_ call: () async throws -> Any) async -> Error {
        do {
            _ = try await call()
        } catch {
            return error
        }
        XCTFail("expected an error")
        return GraphLinkDecodeError("no error")
    }

    func test_aSuccessfulCallReturnsItsData() async throws {
        let item = try await client.queries.item(id: "1")
        XCTAssertEqual(item.name, "Item 1")
    }

    func test_aStatusOnlyErrorIsThrownWithTheFieldsOfTheBody() async {
        let e = await thrownBy { try await client.queries.item(id: "missing") }
        guard let notFound = e as? ItemNotFound else { return XCTFail("got \(e)") }
        XCTAssertTrue(e is GraphLinkDomainError)
        XCTAssertEqual(notFound.id, "missing")
        XCTAssertEqual(notFound.message, "Item missing not found")
    }

    func test_itCanBeCaughtByType() async {
        var caught = ""
        do {
            _ = try await client.queries.item(id: "conflict")
        } catch let e as ItemConflict {
            caught = e.reason
        } catch {
            XCTFail("got \(error)")
        }
        XCTAssertEqual(caught, "duplicate")
    }

    func test_aStatusWithItsOwnValueMatchesTheBodyCode() async {
        let e = await thrownBy { try await client.queries.item(id: "conflict") }
        guard let conflict = e as? ItemConflict else { return XCTFail("got \(e)") }
        XCTAssertEqual(conflict.message, "Conflict")
    }

    func test_aCustomFieldPathIsReadFromTheBody() async {
        let e = await thrownBy { try await client.queries.item(id: "rate") }
        guard let limited = e as? RateLimited else { return XCTFail("got \(e)") }
        XCTAssertEqual(limited.retryAfter, 30)
    }

    func test_aStatusOnlyErrorDoesNotNeedAJsonBody() async {
        let e = await thrownBy { try await client.queries.item(id: "teapot") }
        XCTAssertTrue(e is Teapot, "got \(e)")
    }

    func test_aStatusOnlyErrorWithAnHtmlBodyStillMatchesByStatus() async {
        let e = await thrownBy { try await client.queries.item(id: "html-404") }
        guard let notFound = e as? ItemNotFound else { return XCTFail("got \(e)") }
        XCTAssertNil(notFound.id)
    }

    func test_aMutationThrowsItsDeclaredError() async {
        let e = await thrownBy { try await client.mutations.createItem(input: ItemInput(name: "dup")) }
        guard let conflict = e as? ItemConflict else { return XCTFail("got \(e)") }
        XCTAssertEqual(conflict.reason, "name taken")
    }

    func test_aMutationReturnsItsData() async throws {
        let item = try await client.mutations.createItem(input: ItemInput(name: "fresh"))
        XCTAssertEqual(item.id, "new")
    }

    func test_fallsBackToRestError() async {
        let cases: [(String, Int)] = [
            ("conflict-no-reason", 409), ("conflict-other", 409), ("rate-bad", 429), ("bad-gateway", 502),
        ]
        for (id, status) in cases {
            let e = await thrownBy { try await client.queries.item(id: id) }
            guard let failure = e as? RestError else { XCTFail("\(id): got \(e)"); continue }
            XCTAssertFalse(e is GraphLinkDomainError, id)
            XCTAssertEqual(failure.status, status, id)
        }
    }

    func test_anOperationWithoutThrowsKeepsRestError() async {
        let e = await thrownBy { try await client.queries.itemPlain(id: "x") }
        guard let failure = e as? RestError else { return XCTFail("got \(e)") }
        XCTAssertEqual(failure.status, 404)
    }
}
