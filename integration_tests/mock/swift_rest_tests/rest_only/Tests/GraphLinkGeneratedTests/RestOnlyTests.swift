import XCTest
@testable import GraphLinkGenerated

final class RestOnlyTests: XCTestCase {
    func test_aSchemaWithOnlyRestOperationsNeedsNoGraphqlAdapter() async throws {
        let client = GraphLinkClient(restAdapter: { _ in
            RestResponse.fromText(status: 200, text: #"{"id":"p1","name":"Pen"}"#)
        })
        let product = try await client.queries.product(id: "p1")
        XCTAssertEqual(product?.name, "Pen")
    }
}
