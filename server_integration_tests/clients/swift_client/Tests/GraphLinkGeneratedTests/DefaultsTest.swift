import XCTest
@testable import GraphLinkGenerated

final class DefaultsTest: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newClient()
    }

    func testInputFieldDefaultsAppliedWhenOmitted() async throws {
        let c = try await client.queries.resolveConfig(input: ConfigInput()).resolveConfig
        XCTAssertEqual(c.pageSize, 25)
        XCTAssertEqual(c.ratio, 1.5)
        XCTAssertEqual(c.sort, "asc")
        XCTAssertFalse(c.verbose)
        XCTAssertEqual(c.priority, Priority.medium)
        XCTAssertEqual(c.tags, ["default", "seed"])
        XCTAssertTrue(c.empties.isEmpty)
        XCTAssertNil(c.note)
    }

    func testExplicitValuesOverrideDefaults() async throws {
        let c = try await client.queries.resolveConfig(
            input: ConfigInput(pageSize: 5, sort: "desc", priority: Priority.high, note: "x")
        ).resolveConfig
        XCTAssertEqual(c.pageSize, 5)
        XCTAssertEqual(c.sort, "desc")
        XCTAssertEqual(c.priority, Priority.high)
        XCTAssertEqual(c.note, "x")
    }

    func testNestedObjectArgDefaultMergesWithFieldDefaults() async throws {
        let range = try await client.queries.resolveRange().resolveRange
        XCTAssertEqual(range.min, 5)
        XCTAssertEqual(range.max, 100)
    }

    func testArgumentLevelScalarDefaults() async throws {
        let greetDefault = try await client.queries.greet()
        XCTAssertEqual(greetDefault.greet, "Hi world!")
        let greetCustom = try await client.queries.greet(name: "Bob", times: 2)
        XCTAssertEqual(greetCustom.greet, "Hi Bob!Hi Bob!")
    }

    func testEnumArgumentPassedValueRoundTripsOmittedUsesDefaultHigh() async throws {
        let low = try await client.queries.echoPriority(level: Priority.low)
        XCTAssertEqual(low.echoPriority, Priority.low)
        let defaulted = try await client.queries.echoPriority()
        XCTAssertEqual(defaulted.echoPriority, Priority.high)
    }
}
