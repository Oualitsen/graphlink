import XCTest
@testable import GraphLinkGenerated

private func json(_ e: Echo) throws -> [String: Any] {
    try XCTUnwrap(try bodyJson(e) as? [String: Any])
}

final class JsonBodyTests: RestCase {
    func test_argumentIsTheWholeBodyUnwrapped() async throws {
        let e = try await client.mutations.eJson(body: ProductIn(name: "Pen", price: 2.5, status: .archived, tags: ["a", "b"]))
        XCTAssertEqual([e.method, e.path], ["POST", "/echo/json"])
        XCTAssertTrue(e.contentType?.hasPrefix("application/json") ?? false)
        let decoded = try json(e)
        XCTAssertEqual(decoded["name"] as? String, "Pen")
        XCTAssertEqual(decoded["price"] as? Double, 2.5)
        XCTAssertEqual(decoded["status"] as? String, "ARCHIVED")
        XCTAssertEqual(decoded["tags"] as? [String], ["a", "b"])
        XCTAssertNil(decoded["body"])
    }

    func test_listArgumentIsAJsonArrayEvenWhenEmpty() async throws {
        let e = try await client.mutations.eJsonList(body: [ProductIn(name: "a"), ProductIn(name: "b")])
        XCTAssertEqual((try bodyJson(e) as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["a", "b"])
        let v51 = try await client.mutations.eJsonList(body: [])
        XCTAssertEqual((try bodyJson(v51) as? [Any])?.count, 0)
    }

    func test_nullOptionalBodyMeansNoBodyAndNoContentType() async throws {
        let e = try await client.mutations.eJsonOptional()
        XCTAssertEqual(e.bodySize, 0)
        XCTAssertNil(e.contentType)
        let v52 = try await client.mutations.eJsonOptional(body: ProductIn(name: "x"))
        XCTAssertEqual(try json(v52)["name"] as? String, "x")
    }

    func test_contentTypeOnTheOperationReplacesTheDefault() async throws {
        let e = try await client.mutations.eJsonType(body: ProductIn(name: "x"))
        XCTAssertTrue(e.contentType?.hasPrefix("application/vnd.test+json") ?? false)
    }

    func test_nonAsciiTextRoundTripsAsUtf8() async throws {
        let name = "é漢😀 \"quoted\" \\ back\nline"
        let e = try await client.mutations.eJson(body: ProductIn(name: name))
        XCTAssertEqual(try json(e)["name"] as? String, name)
        XCTAssertEqual(e.bodySize, Data((e.bodyText ?? "").utf8).count)
    }

    func test_largeBodyIsDeliveredIntact() async throws {
        let tags = (0..<20000).map { "tag-\($0)" }
        let e = try await client.mutations.eJson(body: ProductIn(name: "big", tags: tags))
        XCTAssertEqual((try json(e)["tags"] as? [Any])?.count, 20000)
    }

    func test_methodsAndPathVariables() async throws {
        let put = try await client.mutations.ePut(id: "a b", body: ProductIn(name: "x"))
        XCTAssertEqual([put.method, put.path], ["PUT", "/echo/put/a%20b"])
        let patch = try await client.mutations.ePatch(id: "p", body: ProductIn(name: "x"))
        XCTAssertEqual([patch.method, patch.path], ["PATCH", "/echo/patch/p"])
    }

    func test_pathHeaderAndBodyRolesCombine() async throws {
        let e = try await client.mutations.eHeaderBody(id: "i1", tenant: "acme", body: ProductIn(name: "x"))
        XCTAssertEqual(e.path, "/echo/hb/i1")
        XCTAssertEqual(header(e, "x-tenant"), "acme")
        XCTAssertEqual(try json(e)["name"] as? String, "x")
    }
}

final class FormBodyTests: RestCase {
    func test_urlencodedWithScalars() async throws {
        let e = try await client.mutations.eForm(name: "Pen", n: 3)
        XCTAssertEqual(e.method, "POST")
        XCTAssertTrue(e.contentType?.hasPrefix("application/x-www-form-urlencoded") ?? false)
        XCTAssertEqual(formPairs(e), ["name=Pen", "n=3"])
    }

    func test_reservedCharactersRoundTrip() async throws {
        let value = "a&b=c d+e%f/é😀\n"
        let v53 = try await client.mutations.eForm(name: value)
        XCTAssertEqual(formValue(v53, "name"), value)
    }

    func test_listsRepeatOrJoin() async throws {
        let e = try await client.mutations.eForm(name: "n", tags: ["x", "y z"])
        XCTAssertEqual(formPairs(e), ["name=n"] + Variant.list("tags", ["x", "y z"]))
    }

    func test_flatNestsWithTheConfiguredSeparator() async throws {
        let e = try await client.mutations.eForm(name: "n", meta: Meta(name: "m", address: Address(city: "Oran")))
        XCTAssertEqual(formPairs(e).sorted(), [
            "name=n", "\(Variant.key("meta", ["name"]))=m", "\(Variant.key("meta", ["address", "city"]))=Oran",
        ].sorted())
    }

    func test_spreadPutsFieldsAtTopLevelAndJsonIsOneEntry() async throws {
        let e = try await client.mutations.eForm(name: "n", filter: Filter(tag: "t", minPrice: 1))
        XCTAssertEqual(formPairs(e), ["name=n", "tag=t", "minPrice=1.0"])
        let j = try await client.mutations.eForm(name: "n", asJson: Meta(name: "m"))
        let decoded = try JSONSerialization.jsonObject(with: Data((formValue(j, "j") ?? "").utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["name"] as? String, "m")
    }

    func test_nullFieldsOmittedAndAllNullMeansNoBody() async throws {
        let v54 = try await client.mutations.eForm(name: "n")
        XCTAssertEqual(formPairs(v54), ["name=n"])
        let empty = try await client.mutations.eFormEmpty()
        XCTAssertEqual(empty.bodySize, 0)
        XCTAssertNil(empty.contentType)
        let v55 = try await client.mutations.eFormEmpty(b: 0)
        XCTAssertEqual(formPairs(v55), ["b=0"])
    }
}

final class MultipartBodyTests: RestCase {
    func test_textPartHasBoundaryAndNoFilename() async throws {
        let e = try await client.mutations.eMultipart(title: "Hello é")
        XCTAssertTrue(e.contentType?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let title = part(e, "title")
        XCTAssertNil(title.filename)
        XCTAssertEqual(title.text, "Hello é")
    }

    func test_filePartKeepsBytesFilenameAndMimeType() async throws {
        let data = pattern(70000)
        let e = try await client.mutations.eMultipart(one: upload(data, filename: "photo.png", mimeType: "image/png"))
        let p = part(e, "one")
        XCTAssertEqual(p.filename, "photo.png")
        XCTAssertTrue(p.contentType?.hasPrefix("image/png") ?? false)
        XCTAssertEqual(p.size, data.count)
        XCTAssertEqual(p.sha256, sha256Hex(data))
    }

    func test_listOfUploadsRepeatsThePartNameInOrder() async throws {
        let files = [pattern(10), pattern(2000), Data()]
        let e = try await client.mutations.eMultipart(many: files.enumerated().map { upload($1, filename: "f\($0).bin") })
        let parts = partsNamed(e, "many")
        XCTAssertEqual(parts.map(\.filename), ["f0.bin", "f1.bin", "f2.bin"])
        XCTAssertEqual(parts.map(\.size), [10, 2000, 0])
        XCTAssertEqual(parts.map(\.sha256), files.map(sha256Hex))
    }

    func test_nonAsciiFilenameSurvives() async throws {
        let e = try await client.mutations.eMultipart(one: upload(pattern(3), filename: "é漢.png"))
        XCTAssertTrue(["é漢.png", "%C3%A9%E6%BC%A2.png"].contains(part(e, "one").filename ?? ""))
    }

    func test_flatObjectsBecomeTextParts() async throws {
        let e = try await client.mutations.eMultipart(meta: Meta(name: "m", tags: ["a", "b"], address: Address(city: "Oran")))
        XCTAssertEqual(part(e, Variant.key("meta", ["name"])).text, "m")
        XCTAssertEqual(partsNamed(e, Variant.key("meta", ["tags"])).map(\.text), Variant.comma ? ["a,b"] : ["a", "b"])
        XCTAssertEqual(part(e, Variant.key("meta", ["address", "city"])).text, "Oran")
    }

    func test_jsonEncodingIsAPartWithJsonContentType() async throws {
        let e = try await client.mutations.eMultipart(asJson: Meta(name: "m"))
        let p = part(e, "j")
        XCTAssertTrue(p.contentType?.hasPrefix("application/json") ?? false)
        let decoded = try JSONSerialization.jsonObject(with: Data((p.text ?? "").utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["name"] as? String, "m")
    }

    func test_textFileAndObjectPartsTravelTogether() async throws {
        let data = pattern(1000)
        let e = try await client.mutations.eMultipart(
            title: "t", asJson: Meta(name: "m"), one: upload(data, filename: "a.bin"),
            many: [upload(data, filename: "b.bin"), upload(data, filename: "c.bin")]
        )
        XCTAssertEqual(e.parts.map(\.name), ["title", "j", "one", "many", "many"])
    }

    func test_nothingSetMeansNoBody() async throws {
        let e = try await client.mutations.eMultipart()
        XCTAssertEqual(e.bodySize, 0)
        XCTAssertNil(e.contentType)
    }

    func test_progressIncreasesAndEndsAtTheTotal() async throws {
        let data = pattern(1_500_000)
        let reports = Collector<[Int]>()
        let e = try await client.mutations.eMultipart(one: upload(data, filename: "big.bin"), onProgress: { reports.add([$0, $1]) })
        XCTAssertEqual(part(e, "one").sha256, sha256Hex(data))
        let all = reports.all
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.map { $0[0] }, all.map { $0[0] }.sorted())
        XCTAssertEqual(all.last?[0], all.last?[1])
        XCTAssertGreaterThan(all.last?[1] ?? 0, data.count)
    }
}

final class RawBodyTests: RestCase {
    func test_exactlyTheFileBytesWithMimeTypeAndKnownLength() async throws {
        let data = pattern(120_000)
        let e = try await client.mutations.eRaw(file: upload(data, mimeType: "image/png"))
        XCTAssertEqual(e.method, "PUT")
        XCTAssertTrue(e.contentType?.hasPrefix("image/png") ?? false)
        XCTAssertEqual(e.bodySize, data.count)
        XCTAssertEqual(e.bodySha256, sha256Hex(data))
        XCTAssertEqual(e.contentLength, data.count)
        XCTAssertFalse(e.chunked)
    }

    func test_defaultAndOverriddenMimeType() async throws {
        let e = try await client.mutations.eRaw(file: upload(pattern(5)))
        XCTAssertTrue(e.contentType?.hasPrefix("application/octet-stream") ?? false)
        let typed = try await client.mutations.eRawType(file: upload(pattern(5), mimeType: "image/png"))
        XCTAssertTrue(typed.contentType?.hasPrefix("application/x-custom") ?? false)
    }

    func test_emptyFileIsAnEmptyBodyAndNullOptionalMeansNoBody() async throws {
        let v56 = try await client.mutations.eRaw(file: upload(Data())).bodySize
        XCTAssertEqual(v56, 0)
        let e = try await client.mutations.eRawOptional()
        XCTAssertEqual(e.bodySize, 0)
        XCTAssertNil(e.contentType)
    }

    func test_filenameIsNotSent() async throws {
        let e = try await client.mutations.eRaw(file: upload(pattern(5), filename: "secret-name.bin"))
        XCTAssertFalse(e.headers.map(\.value).joined(separator: "|").contains("secret-name"))
        XCTAssertFalse(e.path.contains("secret-name"))
        XCTAssertNil(header(e, "content-disposition"))
    }

    func test_multiMegabyteUploadArrivesIntactWithProgress() async throws {
        let data = pattern(6 * 1024 * 1024)
        let reports = Collector<[Int]>()
        let e = try await client.mutations.eRaw(file: upload(data), onProgress: { reports.add([$0, $1]) })
        XCTAssertEqual(e.bodySha256, sha256Hex(data))
        let all = reports.all
        XCTAssertEqual(all.last, [data.count, data.count])
        XCTAssertEqual(all.map { $0[0] }, all.map { $0[0] }.sorted())
    }
}
