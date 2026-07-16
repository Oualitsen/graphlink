import Foundation
import XCTest
@testable import GraphLinkGenerated

private func makeFile(_ bytes: [UInt8], name: String = "test.png") -> GLUpload {
    GLUpload(data: Data(bytes), mimeType: "image/png", filename: name)
}

final class UploadTest_UploadOneFile: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newUploadClient()
    }

    func test_returnsTrue_whenFileIsProvided() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "user-1", file: makeFile([1, 2, 3]))
        XCTAssertTrue(res.uploadOneFile)
    }

    func test_returnsTrue_forDifferentUserId() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "user-42", file: makeFile([10, 20, 30]))
        XCTAssertTrue(res.uploadOneFile)
    }

    func test_returnsTrue_forLargerFile() async throws {
        let bytes = (0..<1024).map { UInt8($0 % 256) }
        let res = try await client.mutations.uploadOneFile(
            userId: "user-1",
            file: GLUpload(data: Data(bytes), mimeType: "application/octet-stream", filename: "big.bin"))
        XCTAssertTrue(res.uploadOneFile)
    }
}

final class UploadTest_UploadFileList: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newUploadClient()
    }

    func test_returnsTrue_forSingleFileInList() async throws {
        let res = try await client.mutations.uploadFileList(userId: "user-1", files: [makeFile([1, 2, 3])])
        XCTAssertTrue(res.uploadFileList)
    }

    func test_returnsTrue_forTwoFiles() async throws {
        let res = try await client.mutations.uploadFileList(
            userId: "user-1",
            files: [makeFile([1, 2, 3]), makeFile([4, 5, 6], name: "second.png")])
        XCTAssertTrue(res.uploadFileList)
    }

    func test_returnsTrue_forThreeFiles() async throws {
        let res = try await client.mutations.uploadFileList(
            userId: "user-2",
            files: [makeFile([1]), makeFile([2]), makeFile([3])])
        XCTAssertTrue(res.uploadFileList)
    }
}
