import json

from generated import Address, Meta, ProductIn, Status

from . import variant
from .support import (
    RestTestCase,
    form_pairs,
    form_value,
    header,
    part,
    parts_named,
    pattern,
    sha256_of,
    upload_of,
)


def body_json(e):
    return json.loads(e.body_text)


class JsonBody(RestTestCase):
    async def test_argument_is_the_whole_body_unwrapped(self) -> None:
        e = await self.client.mutations.e_json(body=ProductIn(name="Pen", price=2.5, status=Status.ARCHIVED, tags=["a", "b"]))
        self.assertEqual((e.method, e.path), ("POST", "/echo/json"))
        self.assertRegex(e.content_type, r"^application/json")
        decoded = body_json(e)
        self.assertEqual((decoded["name"], decoded["price"], decoded["status"], decoded["tags"]), ("Pen", 2.5, "ARCHIVED", ["a", "b"]))
        self.assertNotIn("body", decoded)

    async def test_list_argument_is_a_json_array_even_when_empty(self) -> None:
        e = await self.client.mutations.e_json_list(body=[ProductIn(name="a"), ProductIn(name="b")])
        self.assertEqual([j["name"] for j in body_json(e)], ["a", "b"])
        self.assertEqual(body_json(await self.client.mutations.e_json_list(body=[])), [])

    async def test_null_optional_body_means_no_body_and_no_content_type(self) -> None:
        e = await self.client.mutations.e_json_optional()
        self.assertEqual(e.body_size, 0)
        self.assertIsNone(e.content_type)
        present = await self.client.mutations.e_json_optional(body=ProductIn(name="x"))
        self.assertEqual(body_json(present)["name"], "x")

    async def test_content_type_on_the_operation_replaces_the_default(self) -> None:
        e = await self.client.mutations.e_json_type(body=ProductIn(name="x"))
        self.assertRegex(e.content_type, r"^application/vnd\.test\+json")

    async def test_non_ascii_text_round_trips_as_utf8(self) -> None:
        name = 'é漢😀 "quoted" \\ back\nline'
        e = await self.client.mutations.e_json(body=ProductIn(name=name))
        self.assertEqual(body_json(e)["name"], name)
        self.assertEqual(e.body_size, len(e.body_text.encode("utf-8")))

    async def test_large_body_is_delivered_intact(self) -> None:
        tags = [f"tag-{i}" for i in range(20000)]
        e = await self.client.mutations.e_json(body=ProductIn(name="big", tags=tags))
        self.assertEqual(len(body_json(e)["tags"]), 20000)

    async def test_methods_and_path_variables(self) -> None:
        put = await self.client.mutations.e_put(id="a b", body=ProductIn(name="x"))
        self.assertEqual((put.method, put.path), ("PUT", "/echo/put/a%20b"))
        patch = await self.client.mutations.e_patch(id="p", body=ProductIn(name="x"))
        self.assertEqual((patch.method, patch.path), ("PATCH", "/echo/patch/p"))

    async def test_path_header_and_body_roles_combine(self) -> None:
        e = await self.client.mutations.e_header_body(id="i1", tenant="acme", body=ProductIn(name="x"))
        self.assertEqual(e.path, "/echo/hb/i1")
        self.assertEqual(header(e, "x-tenant"), "acme")
        self.assertEqual(body_json(e)["name"], "x")


class FormBody(RestTestCase):
    async def test_urlencoded_with_scalars(self) -> None:
        e = await self.client.mutations.e_form(name="Pen", n=3)
        self.assertEqual(e.method, "POST")
        self.assertRegex(e.content_type, r"^application/x-www-form-urlencoded")
        self.assertEqual(form_pairs(e), ["name=Pen", "n=3"])

    async def test_reserved_characters_round_trip(self) -> None:
        value = "a&b=c d+e%f/é😀\n"
        e = await self.client.mutations.e_form(name=value)
        self.assertEqual(form_value(e, "name"), value)

    async def test_lists_repeat_or_join(self) -> None:
        e = await self.client.mutations.e_form(name="n", tags=["x", "y z"])
        self.assertEqual(form_pairs(e), ["name=n", *variant.lst("tags", ["x", "y z"])])

    async def test_flat_nests_with_the_configured_separator(self) -> None:
        e = await self.client.mutations.e_form(name="n", meta=Meta(name="m", address=Address(city="Oran")))
        self.assertEqual(
            form_pairs(e),
            ["name=n", f"{variant.key('meta', ['name'])}=m", f"{variant.key('meta', ['address', 'city'])}=Oran"],
        )

    async def test_spread_puts_fields_at_top_level_and_json_is_one_entry(self) -> None:
        from generated import Filter

        e = await self.client.mutations.e_form(name="n", filter=Filter(tag="t", min_price=1.0))
        self.assertEqual(form_pairs(e), ["name=n", "tag=t", "minPrice=1.0"])
        e = await self.client.mutations.e_form(name="n", as_json=Meta(name="m"))
        self.assertEqual(json.loads(form_value(e, "j") or "")["name"], "m")

    async def test_null_fields_omitted_and_all_null_means_no_body(self) -> None:
        self.assertEqual(form_pairs(await self.client.mutations.e_form(name="n")), ["name=n"])
        empty = await self.client.mutations.e_form_empty()
        self.assertEqual(empty.body_size, 0)
        self.assertIsNone(empty.content_type)
        self.assertEqual(form_pairs(await self.client.mutations.e_form_empty(b=0)), ["b=0"])


class MultipartBody(RestTestCase):
    async def test_text_part_has_boundary_and_no_filename(self) -> None:
        e = await self.client.mutations.e_multipart(title="Hello é")
        self.assertRegex(e.content_type, r"^multipart/form-data; boundary=")
        title = part(e, "title")
        self.assertIsNone(title.filename)
        self.assertEqual(title.text, "Hello é")

    async def test_file_part_keeps_bytes_filename_and_mime_type(self) -> None:
        data = pattern(70000)
        e = await self.client.mutations.e_multipart(one=upload_of(data, "photo.png", "image/png"))
        p = part(e, "one")
        self.assertEqual(p.filename, "photo.png")
        self.assertRegex(p.content_type, r"^image/png")
        self.assertEqual((p.size, p.sha256), (len(data), sha256_of(data)))

    async def test_list_of_uploads_repeats_the_part_name_in_order(self) -> None:
        files = [pattern(10), pattern(2000), b""]
        e = await self.client.mutations.e_multipart(many=[upload_of(f, f"f{i}.bin") for i, f in enumerate(files)])
        parts = parts_named(e, "many")
        self.assertEqual([p.filename for p in parts], ["f0.bin", "f1.bin", "f2.bin"])
        self.assertEqual([p.size for p in parts], [10, 2000, 0])
        self.assertEqual([p.sha256 for p in parts], [sha256_of(f) for f in files])

    async def test_non_ascii_filename_survives(self) -> None:
        e = await self.client.mutations.e_multipart(one=upload_of(pattern(3), "é漢.png"))
        self.assertIn(part(e, "one").filename, ["é漢.png", "%C3%A9%E6%BC%A2.png"])

    async def test_flat_objects_become_text_parts(self) -> None:
        e = await self.client.mutations.e_multipart(meta=Meta(name="m", tags=["a", "b"], address=Address(city="Oran")))
        self.assertEqual(part(e, variant.key("meta", ["name"])).text, "m")
        self.assertEqual([p.text for p in parts_named(e, variant.key("meta", ["tags"]))], ["a,b"] if variant.COMMA else ["a", "b"])
        self.assertEqual(part(e, variant.key("meta", ["address", "city"])).text, "Oran")

    async def test_json_encoding_is_a_part_with_json_content_type(self) -> None:
        e = await self.client.mutations.e_multipart(as_json=Meta(name="m"))
        p = part(e, "j")
        self.assertRegex(p.content_type, r"^application/json")
        self.assertEqual(json.loads(p.text or "")["name"], "m")

    async def test_text_file_and_object_parts_travel_together(self) -> None:
        data = pattern(1000)
        e = await self.client.mutations.e_multipart(
            title="t",
            as_json=Meta(name="m"),
            one=upload_of(data, "a.bin"),
            many=[upload_of(data, "b.bin"), upload_of(data, "c.bin")],
        )
        self.assertEqual([p.name for p in e.parts], ["title", "j", "one", "many", "many"])

    async def test_nothing_set_means_no_body(self) -> None:
        e = await self.client.mutations.e_multipart()
        self.assertEqual(e.body_size, 0)
        self.assertIsNone(e.content_type)

    async def test_progress_increases_and_ends_at_the_total(self) -> None:
        data = pattern(1500000)
        reports = []
        e = await self.client.mutations.e_multipart(
            one=upload_of(data, "big.bin"), on_progress=lambda sent, total: reports.append((sent, total))
        )
        self.assertEqual(part(e, "one").sha256, sha256_of(data))
        self.assertTrue(reports)
        self.assertEqual([r[0] for r in reports], sorted(r[0] for r in reports))
        self.assertEqual(reports[-1][0], reports[-1][1])
        self.assertGreater(reports[-1][1], len(data))


class RawBody(RestTestCase):
    async def test_exactly_the_file_bytes_with_mime_type_and_known_length(self) -> None:
        data = pattern(120000)
        e = await self.client.mutations.e_raw(file=upload_of(data, mime_type="image/png"))
        self.assertEqual(e.method, "PUT")
        self.assertRegex(e.content_type, r"^image/png")
        self.assertEqual((e.body_size, e.body_sha256, e.content_length), (len(data), sha256_of(data), len(data)))
        self.assertFalse(e.chunked)

    async def test_default_and_overridden_mime_type(self) -> None:
        e = await self.client.mutations.e_raw(file=upload_of(pattern(5)))
        self.assertRegex(e.content_type, r"^application/octet-stream")
        e = await self.client.mutations.e_raw_type(file=upload_of(pattern(5), mime_type="image/png"))
        self.assertRegex(e.content_type, r"^application/x-custom")

    async def test_empty_file_is_an_empty_body_and_null_optional_means_no_body(self) -> None:
        self.assertEqual((await self.client.mutations.e_raw(file=upload_of(b""))).body_size, 0)
        e = await self.client.mutations.e_raw_optional()
        self.assertEqual(e.body_size, 0)
        self.assertIsNone(e.content_type)

    async def test_filename_is_not_sent(self) -> None:
        e = await self.client.mutations.e_raw(file=upload_of(pattern(5), "secret-name.bin"))
        self.assertNotIn("secret-name", "|".join(h.value for h in e.headers))
        self.assertNotIn("secret-name", e.path)
        self.assertIsNone(header(e, "content-disposition"))

    async def test_multi_megabyte_upload_arrives_intact_with_progress(self) -> None:
        data = pattern(6 * 1024 * 1024)
        reports = []
        e = await self.client.mutations.e_raw(file=upload_of(data), on_progress=lambda s, t: reports.append((s, t)))
        self.assertEqual(e.body_sha256, sha256_of(data))
        self.assertEqual(reports[-1], (len(data), len(data)))
        self.assertEqual([r[0] for r in reports], sorted(r[0] for r in reports))


async def _chunks(data: bytes, size: int = 16384):
    for offset in range(0, len(data), size):
        yield data[offset : offset + size]


class StreamedUploads(RestTestCase):
    async def test_unknown_length_raw_upload_is_chunked(self) -> None:
        from generated import GLUpload

        data = pattern(250000)
        e = await self.client.mutations.e_raw(file=GLUpload.from_stream(_chunks(data)))
        self.assertTrue(e.chunked)
        self.assertIsNone(e.content_length)
        self.assertEqual(e.body_sha256, sha256_of(data))

    async def test_progress_is_not_reported_when_the_length_is_unknown(self) -> None:
        from generated import GLUpload

        reports = []
        await self.client.mutations.e_raw(
            file=GLUpload.from_stream(_chunks(pattern(40000))), on_progress=lambda s, t: reports.append((s, t))
        )
        self.assertEqual(reports, [])

    async def test_file_is_streamed_from_disk_with_a_known_length(self) -> None:
        import os
        import tempfile

        from generated import GLUpload

        data = pattern(5 * 1024 * 1024)
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
            handle.write(data)
        try:
            upload = GLUpload.from_file(handle.name)
            self.assertEqual(upload.length, len(data))
            self.assertIsNone(upload._bytes)
            e = await self.client.mutations.e_raw(file=upload)
            self.assertEqual(e.body_sha256, sha256_of(data))
            self.assertEqual(e.content_length, len(data))
            self.assertFalse(e.chunked)
            self.assertRegex(e.content_type, r"^image/png")
        finally:
            os.unlink(handle.name)

    async def test_sync_iterable_source_works(self) -> None:
        from generated import GLUpload

        e = await self.client.mutations.e_raw(file=GLUpload.from_stream([b"abc", b"def"], length=6))
        self.assertEqual(e.body_size, 6)
        self.assertEqual(e.body_sha256, sha256_of(b"abcdef"))

    async def test_unknown_length_multipart_part_is_streamed_intact(self) -> None:
        from generated import GLUpload

        data = pattern(300000)
        e = await self.client.mutations.e_multipart(one=GLUpload.from_stream(_chunks(data), filename="u.bin"))
        self.assertEqual(part(e, "one").sha256, sha256_of(data))
        self.assertTrue(e.chunked)

    async def test_multipart_progress_is_not_reported_when_the_total_is_unknown(self) -> None:
        from generated import GLUpload

        reports = []
        await self.client.mutations.e_multipart(
            one=GLUpload.from_stream(_chunks(pattern(40000)), filename="u.bin"), on_progress=lambda s, t: reports.append((s, t))
        )
        self.assertEqual(reports, [])

    async def test_multipart_file_is_not_read_in_full_before_the_first_progress_report(self) -> None:
        import asyncio
        from generated import GLUpload

        data = pattern(6 * 1024 * 1024)
        chunk = 65536
        pulled = 0
        pulled_at_first_report = -1

        async def slow():
            nonlocal pulled
            for offset in range(0, len(data), chunk):
                if offset % (256 * 1024) == 0:
                    await asyncio.sleep(0.002)
                pulled = offset + chunk
                yield data[offset : offset + chunk]

        def on_progress(sent: int, total: int) -> None:
            nonlocal pulled_at_first_report
            if pulled_at_first_report < 0:
                pulled_at_first_report = pulled

        e = await self.client.mutations.e_multipart(
            one=GLUpload.from_stream(slow(), filename="big.bin", length=len(data)), on_progress=on_progress
        )
        self.assertEqual(part(e, "one").sha256, sha256_of(data))
        self.assertGreaterEqual(pulled_at_first_report, 0)
        self.assertLess(pulled_at_first_report, len(data))

    async def test_stream_that_fails_midway_fails_the_call_and_does_not_hang(self) -> None:
        from generated import GLUpload

        async def failing():
            yield pattern(1000)
            raise RuntimeError("source failed")

        with self.assertRaises(Exception):
            await self.client.mutations.e_raw(file=GLUpload.from_stream(failing()))
        self.assertEqual((await self.client.queries.e_accept()).method, "GET")
