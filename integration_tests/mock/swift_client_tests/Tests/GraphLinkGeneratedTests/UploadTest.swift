import Foundation
import XCTest
@testable import GraphLinkGenerated

private func makeFile(_ bytes: [UInt8]) -> GLUpload {
    GLUpload(data: Data(bytes), mimeType: "image/png", filename: "test.png")
}

private func decode(_ jsonString: String) -> [String: Any?] {
    (try? GraphLinkJson.decode(jsonString.data(using: .utf8)!)) ?? [:]
}

/// Values decoded via `JSONSerialization` represent JSON `null` as `NSNull`,
/// not Swift `nil` — this normalizes both forms for assertions.
private func isJSONNull(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}

// ── uploadOneFile ────────────────────────────────────────────────────────────

final class UploadTest_UploadOneFile: XCTestCase {
    var adapter: MockAdapter!
    var multipart: MockMultipartAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        multipart = MockMultipartAdapter()
        client = Fixtures.newClientWithUpload(adapter, MockWebSocketAdapter(), multipart)
        multipart.registerData("uploadOneFile", n(("uploadOneFile", Fixtures.kUserAliceJson)))
    }

    func test_response_id_isCorrect() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertEqual(res.uploadOneFile.id, "user-1")
    }

    func test_response_name_isCorrect() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertEqual(res.uploadOneFile.name, "Alice Smith")
    }

    func test_multipartAdapter_calledOnce() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertEqual(multipart.getCallCount(), 1)
    }

    func test_operations_containsCorrectUserId() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-42", file: makeFile([1, 2, 3]))
        let ops = decode(multipart.getLastCall()!.operations)
        let variables = ops["variables"] as! [String: Any?]
        XCTAssertEqual(variables["userId"] as? String, "user-42")
    }

    func test_fileVariable_isNull_inOperations() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        let ops = decode(multipart.getLastCall()!.operations)
        let variables = ops["variables"] as! [String: Any?]
        XCTAssertTrue(isJSONNull(variables["file"] ?? nil))
    }

    func test_mapSlot0_pointsTo_variablesFile() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        let map = decode(multipart.getLastCall()!.mapJson)
        XCTAssertEqual(map["0"] as? [String], ["variables.file"])
    }

    func test_filePart_presentUnderSlot0() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertTrue(multipart.getLastCall()!.files.keys.contains("0"))
    }

    func test_regularAdapter_notCalled() async throws {
        _ = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertEqual(adapter.getCallCount(), 0)
    }
}

// ── uploadFileList ───────────────────────────────────────────────────────────

final class UploadTest_UploadFileList: XCTestCase {
    var adapter: MockAdapter!
    var multipart: MockMultipartAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        multipart = MockMultipartAdapter()
        client = Fixtures.newClientWithUpload(adapter, MockWebSocketAdapter(), multipart)
        multipart.registerData("uploadFileList", n(("uploadFileList", Fixtures.kUserAliceJson)))
    }

    func test_response_id_isCorrect() async throws {
        let res = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])])
        XCTAssertEqual(res.uploadFileList.id, "user-1")
    }

    func test_filesVariables_areAllNull_inOperations() async throws {
        _ = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])])
        let ops = decode(multipart.getLastCall()!.operations)
        let variables = ops["variables"] as! [String: Any?]
        let files = variables["files"] as! [Any?]
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(isJSONNull(files[0]))
        XCTAssertTrue(isJSONNull(files[1]))
    }

    func test_mapSlot0_pointsTo_variablesFiles0() async throws {
        _ = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])])
        let map = decode(multipart.getLastCall()!.mapJson)
        XCTAssertEqual(map["0"] as? [String], ["variables.files.0"])
    }

    func test_mapSlot1_pointsTo_variablesFiles1() async throws {
        _ = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])])
        let map = decode(multipart.getLastCall()!.mapJson)
        XCTAssertEqual(map["1"] as? [String], ["variables.files.1"])
    }

    func test_bothFileParts_present() async throws {
        _ = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])])
        let files = multipart.getLastCall()!.files
        XCTAssertTrue(files.keys.contains("0"))
        XCTAssertTrue(files.keys.contains("1"))
    }

    func test_singleFileList_producesOneSlot() async throws {
        _ = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3])])
        let map = decode(multipart.getLastCall()!.mapJson)
        XCTAssertEqual(map.count, 1)
    }
}
