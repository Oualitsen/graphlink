import XCTest
@testable import GraphLinkGenerated

final class LenientTests: RestCase {
    func test_nullAndMissingFieldsOfNonNullSchemaFieldsDecodeAsNil() async throws {
        let product = try await client.queries.lenientProduct()
        XCTAssertEqual(product.id, "p1")
        XCTAssertNil(product.name)
        XCTAssertNil(product.price)
        XCTAssertNil(product.tags)
    }

    func test_nestedObjectsAreLenientToo() async throws {
        let product = try await client.queries.lenientProduct()
        let related = try XCTUnwrap(product.related)
        XCTAssertEqual(related.count, 2)
        XCTAssertEqual(related[0].id, "p2")
        XCTAssertNil(related[0].name)
        XCTAssertNil(related[0].related)
        XCTAssertEqual(related[1].name, "Three")
        XCTAssertEqual(related[1].price, 3.5)
        XCTAssertNil(related[1].related)
    }

    func test_listsOfObjectsDecode() async throws {
        let products = try await client.queries.lenientProducts()
        XCTAssertEqual(products.count, 2)
        XCTAssertNil(products[0].name)
        XCTAssertEqual(products[1].name, "B")
    }

    func test_anEmptyBodyIsStillNilBecauseTheSchemaSaysSo() async throws {
        let value = try await client.queries.lenientNothing()
        XCTAssertNil(value)
    }

    func test_interfacesDecodeThroughTheirDiscriminatorWithMissingFields() async throws {
        let pets = try await client.queries.lenientPets()
        XCTAssertEqual(pets.count, 3)

        let first = try XCTUnwrap(pets[0] as? DogRest)
        XCTAssertEqual(first.id, "d1")
        XCTAssertNil(first.name)
        XCTAssertNil(first.barks)

        let second = try XCTUnwrap(pets[1] as? CatRest)
        XCTAssertEqual(second.id, "c1")
        XCTAssertNil(second.name)
        XCTAssertNil(second.lives)

        let third = try XCTUnwrap(pets[2] as? DogRest)
        XCTAssertNil(third.id)
        XCTAssertEqual(third.name, "Rex")
        XCTAssertEqual(third.barks, true)
    }

    func test_unionsDecodeThroughTheirDiscriminator() async throws {
        let hits = try await client.queries.lenientHits()
        XCTAssertEqual((hits[0] as? ProductRest)?.id, "p1")
        let owner = try XCTUnwrap(hits[1] as? OwnerRest)
        XCTAssertEqual(owner.id, "o1")
        XCTAssertNil(owner.name)
    }

    func test_aCachedLenientResultIsStoredAndDecodedTheSameWay() async throws {
        let cached = newClient(store: InMemoryGraphLinkCacheStore())
        let first = try await cached.queries.lenientCached()
        let second = try await cached.queries.lenientCached()
        XCTAssertNil(first.name)
        XCTAssertNil(second.name)
        XCTAssertEqual(second.related?.count, first.related?.count)
        XCTAssertEqual(second.related?[1].name, "Three")
    }
}
