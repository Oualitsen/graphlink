import XCTest
@testable import GraphLinkGenerated

final class HoistArgsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testManyRequiredHoistedArgsInputRenamedCatalogFieldArgs1OnCollision() async throws {
        let catalog = try await client.queries.catalog(
            fieldArgs: CatalogFieldArgs1(productsCategory: "books", productsLimit: 3, productsOffset: 0)
        ).catalog
        XCTAssertEqual(catalog.products.count, 3)
        XCTAssertTrue(catalog.products.allSatisfy { $0.name.hasPrefix("books") })
    }

    func testAllOptionalHoistedArgsCanBeOmittedDefaultItemsLimit10() async throws {
        let feed = try await client.queries.feed().feed
        XCTAssertEqual(feed.items.count, 10)
    }

    func testOptionalHoistedArgsCanBeSupplied() async throws {
        let feed = try await client.queries.feed(fieldArgs: FeedFieldArgs(itemsLimit: 4, itemsSort: "z")).feed
        XCTAssertEqual(feed.items.count, 4)
        XCTAssertTrue(feed.items.first!.name.hasPrefix("z"))
    }

    func testNestedDepthHoistingCollapsesIntoOneInput() async throws {
        let store = try await client.queries.store(fieldArgs: StoreFieldArgs(shelvesFloor: 2, productsLimit: 3)).store
        XCTAssertEqual(store.shelves.count, 2)
        XCTAssertEqual(store.shelves.first!.products.count, 3)
    }

    func testParamNameCollisionUsesFieldArgs1ForSyntheticArg() async throws {
        let search = try await client.queries.search(fieldArgs: "q", fieldArgs1: SearchFieldArgs(hitsLimit: 3)).search
        XCTAssertEqual(search.id, "q")
        XCTAssertEqual(search.hits.count, 3)
    }
}
