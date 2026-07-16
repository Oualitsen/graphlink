import Foundation
import XCTest
@testable import GraphLinkGenerated

final class ScalarsTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable scalar fields ────────────────────────────────────────────

    func test_NonNullableScalarFields_id_deserializesToString() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertEqual(s.id, "scalar-1")
    }

    func test_NonNullableScalarFields_strVal_deserializesToString() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertEqual(s.strVal, "hello world")
    }

    func test_NonNullableScalarFields_intVal_deserializesToInt() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertEqual(s.intVal, 42)
    }

    func test_NonNullableScalarFields_floatVal_deserializesToDouble() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertEqual(s.floatVal, 3.14, accuracy: 0.001)
    }

    func test_NonNullableScalarFields_boolVal_deserializesToBoolean() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertTrue(s.boolVal)
    }

    // ── Nullable scalar fields — null in response ─────────────────────────────

    func test_NullableScalarFields_Null_nullableStr_isNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertNil(s.nullableStr)
    }

    func test_NullableScalarFields_Null_nullableInt_isNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertNil(s.nullableInt)
    }

    func test_NullableScalarFields_Null_nullableFloat_isNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertNil(s.nullableFloat)
    }

    func test_NullableScalarFields_Null_nullableBool_isNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertNil(s.nullableBool)
    }

    func test_NullableScalarFields_Null_nullableId_isNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-1").getAllScalars
        XCTAssertNil(s.nullableId)
    }

    // ── Nullable scalar fields — values present ───────────────────────────────

    func test_NullableScalarFields_Present_nullableStr_hasValue() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertEqual(s.nullableStr, "present")
    }

    func test_NullableScalarFields_Present_nullableInt_hasValue() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertEqual(s.nullableInt, 99)
    }

    func test_NullableScalarFields_Present_nullableFloat_hasValue() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertEqual(s.nullableFloat!, 2.718, accuracy: 0.001)
    }

    func test_NullableScalarFields_Present_nullableBool_isFalse_notNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        let v = s.nullableBool
        XCTAssertNotNil(v)
        XCTAssertFalse(v!)
    }

    func test_NullableScalarFields_Present_negativeInt_deserializesCorrectly() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertEqual(s.intVal, -1)
    }

    func test_NullableScalarFields_Present_negativeFloat_deserializesCorrectly() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertEqual(s.floatVal, -0.5, accuracy: 0.001)
    }

    func test_NullableScalarFields_Present_boolFalse_isNotTreatedAsNull() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsPresentJson)))
        let s = try await client.queries.getAllScalars(id: "scalar-2").getAllScalars
        XCTAssertFalse(s.boolVal)
    }

    // ── Outgoing request shape ────────────────────────────────────────────────

    func test_OutgoingRequestShape_idArgument_isSentAsStringInVariables() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        _ = try await client.queries.getAllScalars(id: "scalar-1")
        XCTAssertEqual(adapter.getLastCall()?.variables["id"] as? String, "scalar-1")
    }

    func test_OutgoingRequestShape_operationName_isGetAllScalars() async throws {
        adapter.registerData("getAllScalars", n(("getAllScalars", Fixtures.kAllScalarsNullJson)))
        _ = try await client.queries.getAllScalars(id: "scalar-1")
        XCTAssertEqual(adapter.getLastCall()?.operationName, "getAllScalars")
    }
}
