import Foundation
import XCTest
@testable import GraphLinkGenerated

final class UploadStreamingTests: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = newClient(recordingUrl)
    }

    func test_a6MBFileArrivesIntactWithoutProgress() async throws {
        let data = pattern(6 * 1024 * 1024)
        let res = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(data, filename: "big.bin"))
        XCTAssertTrue(res.uploadOneFile)
        let sent = try await lastRequest()
        XCTAssertEqual(sent.part("0").sha256, sha256Hex(data))
        XCTAssertEqual(sent.part("0").filename, "big.bin")
        XCTAssertTrue(sent.part("operations").text?.contains("\"userId\":\"u1\"") ?? false)
    }

    func test_aFileOfKnownLengthIsSentWithAContentLength() async throws {
        let data = pattern(300_000)
        _ = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(data, filename: "a.bin"))
        let sent = try await lastRequest()
        XCTAssertFalse(sent.chunked)
        XCTAssertGreaterThan(sent.contentLength ?? 0, data.count)
    }

    func test_aFileOfUnknownLengthArrivesIntactSentChunked() async throws {
        let data = pattern(300_000)
        _ = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(data, filename: "a.bin", knownLength: false))
        let sent = try await lastRequest()
        XCTAssertEqual(sent.part("0").sha256, sha256Hex(data))
        XCTAssertTrue(sent.chunked)
    }

    func test_a6MBFileArrivesIntactWithProgress() async throws {
        let data = pattern(6 * 1024 * 1024)
        _ = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(data, filename: "big.bin"), onProgress: { _, _ in })
        let sent = try await lastRequest()
        XCTAssertEqual(sent.part("0").sha256, sha256Hex(data))
    }

    func test_progressIncreasesAndEndsAtTheTotal() async throws {
        let data = pattern(6 * 1024 * 1024)
        let reports = Collector<[Int]>()
        _ = try await client.mutations.uploadOneFile(
            userId: "u1",
            file: streamedUpload(data, filename: "big.bin"),
            onProgress: { reports.add([$0, $1]) }
        )
        let all = reports.all
        XCTAssertGreaterThanOrEqual(all.count, 2)
        XCTAssertEqual(all.map { $0[0] }, all.map { $0[0] }.sorted())
        XCTAssertEqual(all.last?[0], all.last?[1])
        XCTAssertGreaterThan(all.last?[1] ?? 0, data.count)
        let sent = try await lastRequest()
        XCTAssertEqual(all.last?[1], sent.contentLength)
    }

    func test_theFileIsNotReadInFullBeforeTheFirstProgressReport() async throws {
        let data = pattern(6 * 1024 * 1024)
        let pulled = Collector<Int>()
        let atFirstReport = Collector<Int>()
        _ = try await client.mutations.uploadOneFile(
            userId: "u1",
            file: streamedUpload(data, filename: "big.bin", onPull: { pulled.add($0) }, pauseEvery: 256 * 1024),
            onProgress: { _, _ in if atFirstReport.all.isEmpty { atFirstReport.add(pulled.all.last ?? 0) } }
        )
        XCTAssertLessThan(atFirstReport.all.first ?? Int.max, data.count)
    }

    func test_aFileOfUnknownLengthFiresNoProgressAndArrivesIntact() async throws {
        let data = pattern(300_000)
        let reports = Collector<[Int]>()
        _ = try await client.mutations.uploadOneFile(
            userId: "u1",
            file: streamedUpload(data, filename: "a.bin", knownLength: false),
            onProgress: { reports.add([$0, $1]) }
        )
        let sent = try await lastRequest()
        XCTAssertEqual(sent.part("0").sha256, sha256Hex(data))
        XCTAssertTrue(sent.chunked)
        XCTAssertTrue(reports.all.isEmpty)
    }

    func test_twoFilesArriveIntactInSlotOrderWithProgress() async throws {
        let first = pattern(1_200_000)
        let second = Data(pattern(900_000).reversed())
        let reports = Collector<[Int]>()
        let res = try await client.mutations.uploadFileList(
            userId: "u1",
            files: [streamedUpload(first, filename: "a.bin"), streamedUpload(second, filename: "b.bin")],
            onProgress: { reports.add([$0, $1]) }
        )
        XCTAssertTrue(res.uploadFileList)
        let sent = try await lastRequest()
        XCTAssertEqual(sent.part("0").sha256, sha256Hex(first))
        XCTAssertEqual(sent.part("0").filename, "a.bin")
        XCTAssertEqual(sent.part("1").sha256, sha256Hex(second))
        XCTAssertEqual(sent.part("1").filename, "b.bin")
        XCTAssertEqual(reports.all.last?[0], reports.all.last?[1])
    }
}

final class SpringServerUploadTests: XCTestCase {
    var client: GraphLinkClient!

    override func setUpWithError() throws {
        guard let url = springUrl else { throw XCTSkip("UPLOAD_SERVER_URL not set") }
        client = newClient(url)
    }

    func test_aFileOfKnownLengthIsAccepted() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(pattern(3_000_000), filename: "f.bin"), onProgress: { _, _ in })
        XCTAssertTrue(res.uploadOneFile)
    }

    func test_aFileOfUnknownLengthIsAcceptedChunked() async throws {
        let res = try await client.mutations.uploadOneFile(userId: "u1", file: streamedUpload(pattern(3_000_000), filename: "f.bin", knownLength: false))
        XCTAssertTrue(res.uploadOneFile)
    }

    func test_aListOfFilesIsAccepted() async throws {
        let res = try await client.mutations.uploadFileList(
            userId: "u1",
            files: [streamedUpload(pattern(1000), filename: "a.bin"), streamedUpload(pattern(2000), filename: "b.bin", knownLength: false)]
        )
        XCTAssertTrue(res.uploadFileList)
    }
}
