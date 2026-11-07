import XCTest
@testable import GraphLinkGenerated

private func kinds<T>(_ values: [T]) -> [String] {
    values.map { value in
        switch value as Any {
        case is Dog: return "Dog"
        case is Cat: return "Cat"
        case is Product: return "Product"
        case is Owner: return "Owner"
        default: return "other"
        }
    }
}

private func optionalKinds(_ values: [Pet?]) -> [String] {
    values.map { $0 == nil ? "nil" : kinds([$0!])[0] }
}

final class PolymorphismNestedTests: RestCase {
    func test_interfaceAndUnionFieldsInsideAnObject() async throws {
        let kennel = try await client.queries.kennel()
        XCTAssertEqual((kennel.resident as? Dog)?.barks, true)
        XCTAssertEqual((kennel.hit as? Product)?.name, "Pen")
    }

    func test_listsOfInterfacesAndUnionsInsideAnObject() async throws {
        let kennel = try await client.queries.kennel()
        XCTAssertEqual(kinds(kennel.featured), ["Dog", "Cat"])
        XCTAssertEqual((kennel.featured[1] as? Cat)?.lives, 9)
        XCTAssertEqual(kinds(try XCTUnwrap(kennel.hits)), ["Product", "Owner"])
    }

    func test_nullElementsInAListOfInterfaces() async throws {
        let kennel = try await client.queries.kennel()
        XCTAssertEqual(optionalKinds(try XCTUnwrap(kennel.mixed)), ["Dog", "nil", "Cat"])
    }

    func test_nullPolymorphicFields() async throws {
        let empty = try await client.queries.shelter().kennels[1]
        XCTAssertNil(empty.resident)
        XCTAssertTrue(empty.featured.isEmpty)
        XCTAssertNil(empty.mixed)
        XCTAssertNil(empty.hit)
        XCTAssertNil(empty.hits)
    }

    func test_twoLevelsDeep() async throws {
        let shelter = try await client.queries.shelter()
        XCTAssertEqual(shelter.kennels.count, 2)
        XCTAssertTrue(shelter.kennels[0].resident is Dog)
        XCTAssertEqual(shelter.kennels[0].featured[1].name, "Tom")
    }
}

final class PolymorphismResultTests: RestCase {
    func test_nullableElementsKeepNil() async throws {
        let pets = try await client.queries.petsNullable()
        XCTAssertEqual(optionalKinds(pets), ["Dog", "nil", "Cat"])
    }

    func test_optionalListDecodesAJsonNullAsNil() async throws {
        let pets = try await client.queries.petsOptional()
        XCTAssertNil(pets)
    }

    func test_throughResponsePath() async throws {
        let pets = try await client.queries.petsWrapped()
        XCTAssertEqual(kinds(pets), ["Dog", "Cat"])
    }

    func test_fromAMutation() async throws {
        let pet = try await client.mutations.adoptPet(id: "c9")
        XCTAssertTrue(pet is Cat)
        XCTAssertEqual(pet.id, "c9")
        XCTAssertEqual(pet.name, "Adopted")
    }

    func test_fromACachedOperation() async throws {
        let first = try await client.queries.cachedPet(id: "d7")
        let second = try await client.queries.cachedPet(id: "d7")
        XCTAssertTrue(first is Dog)
        XCTAssertEqual(first?.name, "Rex1")
        XCTAssertEqual(second?.name, "Rex1")
        let other = try await client.queries.cachedPet(id: "d8")
        XCTAssertEqual(other?.name, "Rex1")
    }
}

final class PolymorphismPayloadTests: RestCase {
    private func failure(_ call: () async throws -> Void) async -> String {
        do {
            try await call()
            XCTFail("expected the decode to fail")
            return ""
        } catch {
            return String(describing: error)
        }
    }

    func test_unknownDiscriminatorValueIsAnErrorNamingTheParentAndTheValue() async {
        let message = await failure { _ = try await self.client.queries.petsUnknown() }
        XCTAssertTrue(message.contains("Pet"), message)
        XCTAssertTrue(message.contains("bird"), message)
    }

    func test_discriminatorKeyAbsentIsAnErrorNamingTheParentAndTheKey() async {
        let message = await failure { _ = try await self.client.queries.petNoKind() }
        XCTAssertTrue(message.contains("Pet") && message.contains("kind"), message)
    }

    func test_discriminatorNullIsAnErrorNamingTheParentAndTheKey() async {
        let message = await failure { _ = try await self.client.queries.petNullKind() }
        XCTAssertTrue(message.contains("Pet") && message.contains("kind"), message)
    }

    func test_aFailedDecodeDoesNotPoisonTheNextCall() async throws {
        _ = await failure { _ = try await self.client.queries.petsUnknown() }
        let pet = try await client.queries.petExtraKeys()
        XCTAssertTrue(pet is Dog)
    }

    func test_unknownKeysInsideAMemberAreIgnored() async throws {
        let pet = try await client.queries.petExtraKeys()
        XCTAssertTrue(pet is Dog)
        XCTAssertEqual(pet.name, "Rex")
    }
}
