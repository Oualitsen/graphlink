import XCTest
@testable import GraphLinkGenerated

final class DownloadTests: RestCase {
    func test_metadataFromHeadersAndExactBytes() async throws {
        let d = try await client.queries.blob(size: 100_000)
        XCTAssertEqual(d.filename, "blob-100000.bin")
        XCTAssertTrue(d.contentType?.hasPrefix("application/octet-stream") ?? false)
        XCTAssertEqual(d.length, 100_000)
        let v57 = try await d.data()
        XCTAssertEqual(v57, pattern(100_000))
    }

    func test_multiMegabyteDownloadIsStreamedAndIntact() async throws {
        let size = 3 * 1024 * 1024
        let d = try await client.queries.blob(size: size)
        var all = Data()
        var chunks = 0
        for try await chunk in d.stream {
            all.append(chunk)
            chunks += 1
        }
        XCTAssertGreaterThan(chunks, 1)
        XCTAssertEqual(sha256Hex(all), sha256Hex(pattern(size)))
    }

    func test_progressEndsAtTheTotal() async throws {
        let reports = Collector<[Int]>()
        let d = try await client.queries.blob(size: 500_000, onReceiveProgress: { reports.add([$0, $1]) })
        _ = try await d.data()
        XCTAssertEqual(reports.all.last, [500_000, 500_000])
        XCTAssertEqual(reports.all.map { $0[0] }, reports.all.map { $0[0] }.sorted())
    }

    func test_emptyDownload() async throws {
        let v58 = try await client.queries.blob(size: 0).data().count
        XCTAssertEqual(v58, 0)
    }

    func test_missingResourceIsARestError() async throws {
        let failure = await capture { try await self.client.queries.avatar(id: "p1") }
        XCTAssertEqual((failure as? RestError)?.status, 404)
    }

    func test_uploadAndMatchingDownloadRoundTrip() async throws {
        let data = pattern(70_000)
        try await client.mutations.uploadAvatar(id: "p1", file: upload(data, mimeType: "image/png"))
        let d = try await client.queries.avatar(id: "p1")
        XCTAssertTrue(d.contentType?.hasPrefix("image/png") ?? false)
        XCTAssertEqual(d.filename, "p1.png")
        let v59 = try await d.data()
        XCTAssertEqual(v59, data)
    }

    func test_nullableDownloadIsNullOn204AndPresentAfterwards() async throws {
        let none = try await client.queries.avatarOrEmpty(id: "p1")
        XCTAssertNil(none)
        try await client.mutations.uploadAvatar(id: "p1", file: upload(pattern(10)))
        let v60 = try await client.queries.avatarOrEmpty(id: "p1")?.data()
        XCTAssertEqual(v60, pattern(10))
    }

    func test_severalDownloadsCanBeOpenAtOnce() async throws {
        let c = client!
        let sizes = try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 1...5 { group.addTask { try await c.queries.blob(size: i * 1000).data().count } }
            var out: [Int] = []
            for try await n in group { out.append(n) }
            return out.sorted()
        }
        XCTAssertEqual(sizes, [1000, 2000, 3000, 4000, 5000])
    }
}

final class CrudFlowTests: RestCase {
    func test_productLifecycle() async throws {
        let created = try await client.mutations.createProduct(input: ProductIn(name: "Lamp", price: 30, tags: ["home"]))
        XCTAssertEqual(created.name, "Lamp")
        XCTAssertEqual(created.status, .active)
        let v61 = try await client.queries.product(id: created.id)?.price
        XCTAssertEqual(v61, 30)
        let v62 = try await client.queries.products(filter: Filter(tag: "home")).map(\.id)
        XCTAssertEqual(v62, [created.id])
        let v63 = try await client.queries.products(ids: ["p1", created.id]).map(\.id)
        XCTAssertEqual(Set(v63), ["p1", created.id])
        let patched = try await client.mutations.patchProduct(id: created.id, input: ProductIn(name: "Lamp 2", price: 35))
        XCTAssertEqual([patched.name], ["Lamp 2"])
        XCTAssertEqual(patched.price, 35)
        let renamed = try await client.mutations.renameProduct(id: created.id, name: "Lamp 3", note: "n")
        XCTAssertEqual(renamed.name, "Lamp 3")
        XCTAssertEqual(renamed.tags, ["n"])
        let gallery = try await client.mutations.gallery(
            id: created.id, title: "Gallery é",
            files: [upload(pattern(100), filename: "a.png"), upload(pattern(200), filename: "b.png")]
        )
        XCTAssertEqual(gallery.name, "Gallery é")
        XCTAssertEqual(gallery.tags, ["a.png", "b.png"])
        let v64 = try await client.mutations.replaceProduct(id: created.id, input: ProductIn(name: "Final")).name
        XCTAssertEqual(v64, "Final")
        try await client.mutations.deleteProduct(id: created.id)
        let failure = await capture { try await self.client.queries.product(id: created.id) }
        XCTAssertEqual((failure as? RestError)?.status, 404)
    }

    func test_voidSucceedsOn204AndFailsOnAMissingResource() async throws {
        try await client.mutations.deleteProduct(id: "p2")
        let failure = await capture { try await self.client.mutations.deleteProduct(id: "p2") }
        XCTAssertEqual((failure as? RestError)?.status, 404)
    }

    func test_sameClientServesManyConcurrentCalls() async throws {
        let c = client!
        let results = try await withThrowingTaskGroup(of: Product.self) { group in
            for i in 0..<40 { group.addTask { try await c.mutations.createProduct(input: ProductIn(name: "item-\(i)")) } }
            var out: [Product] = []
            for try await p in group { out.append(p) }
            return out
        }
        XCTAssertEqual(Set(results.map(\.name)).count, 40)
        XCTAssertEqual(Set(results.map(\.id)).count, 40)
        let v65 = try await client.queries.products().count
        XCTAssertEqual(v65, 42)
    }

    func test_productsListWithNoFilters() async throws {
        let v66 = try await client.queries.products().map(\.id)
        XCTAssertEqual(v66, ["p1", "p2"])
    }
}
