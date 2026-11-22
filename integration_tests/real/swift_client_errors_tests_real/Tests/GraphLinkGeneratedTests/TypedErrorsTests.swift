import Foundation
import XCTest
@testable import GraphLinkGenerated

final class TypedErrorsTests: XCTestCase {
    let client = GraphLinkClient(adapter: DefaultGraphLinkURLSessionAdapter(url: URL(string: "http://127.0.0.1:9930/graphql")!).execute)

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
        let res = try await client.queries.article(id: "1")
        XCTAssertEqual(res.article?.id, "1")
    }

    func test_aDeclaredErrorIsThrownAsItsClassWithItsFields() async {
        let e = await thrownBy { try await client.queries.article(id: "missing") }
        guard let notFound = e as? ArticleNotFound else { return XCTFail("got \(e)") }
        XCTAssertTrue(e is GraphLinkDomainError)
        XCTAssertEqual(notFound.id, "missing")
        XCTAssertEqual(notFound.message, "Article missing not found")
    }

    func test_itCanBeCaughtByType() async {
        var caught = ""
        do {
            _ = try await client.queries.article(id: "missing")
        } catch let e as ArticleNotFound {
            caught = e.id
        } catch {
            XCTFail("got \(error)")
        }
        XCTAssertEqual(caught, "missing")
    }

    func test_anErrorMatchedOnACustomFieldAndValue() async {
        let e = await thrownBy { try await client.queries.article(id: "forbidden") }
        XCTAssertEqual((e as? Forbidden)?.message, "No access")
    }

    func test_anErrorOfAnotherRootField() async {
        let e = await thrownBy { try await client.queries.secret() }
        XCTAssertTrue(e is Forbidden)
    }

    func test_fallbacksKeepTheException() async {
        for id in ["other-code", "no-field", "no-path", "no-extensions"] {
            let e = await thrownBy { try await client.queries.article(id: id) }
            XCTAssertTrue(e is GraphLinkException, id)
            XCTAssertFalse(e is GraphLinkDomainError, id)
        }
    }

    func test_anUnknownCodeKeepsItsMessage() async {
        let e = await thrownBy { try await client.queries.article(id: "other-code") }
        XCTAssertEqual((e as? GraphLinkException)?.errors.first?.message, "A new error")
    }

    func test_anOperationWithoutThrowsKeepsTheException() async {
        let e = await thrownBy { try await client.queries.plain(id: "1") }
        XCTAssertTrue(e is GraphLinkException)
        XCTAssertFalse(e is GraphLinkDomainError)
    }

    func test_aCombinedQueryKeepsTheException() async {
        let e = await thrownBy { try await client.queries.pair() }
        let path = (e as? GraphLinkException)?.errors.first?.path
        XCTAssertEqual(path?.first as? String, "first")
    }

    func test_aCaptureErrorsOperationReturnsTheErrors() async throws {
        let res = try await client.queries.captured()
        XCTAssertEqual(res.errors?.first?.extensions?["code"] as? String, "ArticleNotFound")
    }

    func test_aMutationReturnsItsData() async throws {
        let res = try await client.mutations.createArticle(input: ArticleInput(title: "fresh"))
        XCTAssertEqual(res.createArticle?.id, "fresh")
    }

    func test_aDeclaredErrorCarriesAListField() async {
        let e = await thrownBy { try await client.mutations.createArticle(input: ArticleInput(title: "taken")) }
        let taken = e as? TitleTaken
        XCTAssertEqual(taken?.title, "taken")
        XCTAssertEqual(taken?.suggestions, ["taken-2"])
    }

    func test_anErrorWithItsOwnValueAnEnumAndAnOptionalField() async {
        let e = await thrownBy { try await client.mutations.createArticle(input: ArticleInput(title: "banned")) }
        let banned = e as? Banned
        XCTAssertEqual(banned?.reason, .spam)
        XCTAssertEqual(banned?.until, 5)
    }
}
