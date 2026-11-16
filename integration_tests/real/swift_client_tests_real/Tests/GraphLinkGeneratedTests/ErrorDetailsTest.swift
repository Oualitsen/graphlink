import Foundation
import XCTest
@testable import GraphLinkGenerated

final class ErrorDetailsTest: XCTestCase {

    func testErrorCarriesMessagePathLocationsAndTypedExtensions() async throws {
        let client = Fixtures.newRealClient()
        let res = try await client.queries.getUserOrErrors(id: "missing")
        XCTAssertEqual(res.errors?.count, 1)
        let e = try XCTUnwrap(res.errors?.first)
        XCTAssertEqual(e.message, "User not found: missing")
        XCTAssertEqual(e.path?.compactMap { $0 as? String }, ["getUserOrErrors"])
        XCTAssertEqual(e.locations?.first?.line, 1)
        XCTAssertEqual(e.extensions?["code"] as? String, "NOT_FOUND")
        XCTAssertEqual(e.extensions?["retryable"] as? Bool, false)
        let detail = try XCTUnwrap(e.extensions?["detail"] as? [String: Any])
        XCTAssertEqual(detail["id"] as? String, "missing")
        XCTAssertEqual(detail["attempts"] as? Int, 3)
    }

    func testPartialDataOkIsReturnedBadIsNullAndTheErrorPathIsTheAlias() async throws {
        let client = Fixtures.newRealClient()
        let res = try await client.queries.partialAliased()
        XCTAssertEqual(res.data?.ok.id, "user-1")
        XCTAssertNil(res.data?.bad)
        XCTAssertEqual(res.errors?.count, 1)
        XCTAssertEqual(res.errors?.first?.path?.compactMap { $0 as? String }, ["bad"])
    }
}
