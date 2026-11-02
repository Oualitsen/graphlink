import asyncio
import unittest

from generated import (
    Filter,
    Auth,
    Group,
    ProductIn,
    RestError,
    RestFormBody,
    RestMultipartBody,
    Status,
)

from .mock_rest import MockRest, bytes_upload, client_for, query_string

PRODUCT = {"id": "p1", "name": "Pen", "price": 2.5, "status": "ACTIVE", "tags": ["a", "b"]}


class RestMockCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.rest = MockRest()
        self.client = client_for(self.rest)


class Requests(RestMockCase):
    async def test_path_variable_is_encoded_and_enum_query_value_sent(self) -> None:
        self.rest.on("GET", "/products/a%20b", json_body=PRODUCT)
        result = await self.client.queries.product(id="a b", status=Status.ARCHIVED)
        self.assertEqual(result.name, "Pen")
        self.assertEqual(self.rest.last.method, "GET")
        self.assertEqual(query_string(self.rest.last), "status=ARCHIVED")
        self.assertEqual(self.rest.last.headers["Accept"], "application/json")
        self.assertIsNone(self.rest.last.body)
        self.assertNotIn("Content-Type", self.rest.last.headers)

    async def test_defaults_lists_and_spreads(self) -> None:
        self.rest.on("GET", "/products", json_body=[PRODUCT])
        await self.client.queries.products(
            filter=Filter(tag="x", min_price=3.0), ids=["1", "2"], auth=Auth(token="t", request_id="r1")
        )
        self.assertEqual(query_string(self.rest.last), "tag=x&minPrice=3.0&page=1&ids=1&ids=2")
        self.assertEqual(self.rest.last.headers["token"], "t")
        self.assertEqual(self.rest.last.headers["X-Request-Id"], "r1")

    async def test_null_optionals_are_omitted(self) -> None:
        self.rest.on("GET", "/products", json_body=[])
        await self.client.queries.products()
        self.assertEqual(query_string(self.rest.last), "page=1")

    async def test_flat_objects_in_a_list_use_indexed_keys(self) -> None:
        self.rest.on("GET", "/products/search", json_body={"data": {"total": 1, "items": [PRODUCT]}})
        page = await self.client.queries.search(
            q="pen", groups=[Group(name="g", ids=[1, 2]), Group(name="h")], tags=["x", "y"]
        )
        self.assertEqual(
            query_string(self.rest.last),
            "q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y",
        )
        self.assertEqual((page.total, page.items[0].id), (1, "p1"))

    async def test_json_body_is_the_argument_itself(self) -> None:
        import json

        self.rest.on("POST", "/products", status=201, json_body=PRODUCT)
        created = await self.client.mutations.create_product(input=ProductIn(name="Pen", price=2.5))
        self.assertEqual(created.id, "p1")
        decoded = json.loads(self.rest.bodies[0])
        self.assertEqual((decoded["name"], decoded["price"]), ("Pen", 2.5))
        self.assertEqual(self.rest.last.headers["Content-Type"], "application/json")

    async def test_form_body_carries_only_non_null_fields(self) -> None:
        self.rest.on("POST", "/products/p1/rename", json_body=PRODUCT)
        await self.client.mutations.rename(id="p1", name="New")
        body = self.rest.last.body
        self.assertIsInstance(body, RestFormBody)
        self.assertEqual(body.fields, [("name", "New")])
        self.assertEqual(self.rest.last.headers["Content-Type"], "application/x-www-form-urlencoded")

    async def test_multipart_carries_text_and_file_parts(self) -> None:
        self.rest.on("POST", "/products/p1/gallery", json_body=PRODUCT)
        await self.client.mutations.gallery(
            id="p1", title="T", files=[bytes_upload("1", "a.png"), bytes_upload("2", "b.png")]
        )
        body = self.rest.last.body
        self.assertIsInstance(body, RestMultipartBody)
        self.assertEqual([p.name for p in body.parts], ["title", "files", "files"])
        self.assertEqual(body.parts[0].value, "T")
        self.assertEqual(body.parts[2].file.filename, "b.png")
        self.assertNotIn("Content-Type", self.rest.last.headers)

    async def test_raw_body_carries_the_upload_with_its_mime_type(self) -> None:
        self.rest.on("PUT", "/products/p1/avatar", status=204)
        await self.client.mutations.avatar(id="p1", file=bytes_upload("bytes", mime_type="image/png"))
        self.assertEqual(self.rest.bodies[0], "bytes")
        self.assertEqual(self.rest.last.headers["Content-Type"], "image/png")


class Responses(RestMockCase):
    async def test_void_accepts_any_2xx_and_ignores_the_body(self) -> None:
        self.rest.on("DELETE", "/products/p1", text="whatever")
        await self.client.mutations.delete_product(id="p1")
        self.assertEqual(self.rest.last.method, "DELETE")

    async def test_nullable_result_with_an_empty_body_is_null(self) -> None:
        self.rest.on("GET", "/products/p1", status=204)
        self.assertIsNone(await self.client.queries.product(id="p1"))

    async def test_non_null_result_with_an_empty_body_is_an_error(self) -> None:
        self.rest.on("GET", "/products/count")
        with self.assertRaisesRegex(ValueError, "Empty REST response"):
            await self.client.queries.count()

    async def test_non_2xx_raises_rest_error(self) -> None:
        self.rest.on("GET", "/products/p1", status=404, text="nope", headers={"x-a": "b"})
        with self.assertRaises(RestError) as caught:
            await self.client.queries.product(id="p1")
        error = caught.exception
        self.assertEqual((error.status, error.body, error.headers["x-a"]), (404, "nope", "b"))

    async def test_text_and_scalar_results(self) -> None:
        self.rest.on("GET", "/products/p1/note", text="hello")
        self.assertEqual(await self.client.queries.note(id="p1"), "hello")
        self.rest.on("GET", "/products/count", json_body=7)
        self.assertEqual(await self.client.queries.count(), 7)


class Cache(RestMockCase):
    async def test_cached_get_query_hits_the_adapter_once(self) -> None:
        self.rest.on("GET", "/products/cached/p1", json_body=PRODUCT)
        await self.client.queries.cached(id="p1")
        await self.client.queries.cached(id="p1")
        self.assertEqual(len(self.rest.calls), 1)
        self.rest.on("GET", "/products/cached/p2", json_body=PRODUCT)
        await self.client.queries.cached(id="p2")
        self.assertEqual(len(self.rest.calls), 2)

    async def test_mutation_invalidates_the_tag_after_a_2xx(self) -> None:
        self.rest.on("GET", "/products/cached/p1", json_body=PRODUCT)
        self.rest.on("PUT", "/products/cached/p1", json_body=PRODUCT)
        await self.client.queries.cached(id="p1")
        await self.client.mutations.update_cached(id="p1", input=ProductIn(name="x"))
        await self.client.queries.cached(id="p1")
        self.assertEqual(len([c for c in self.rest.calls if c.method == "GET"]), 2)

    async def test_failed_mutation_does_not_invalidate(self) -> None:
        self.rest.on("GET", "/products/cached/p1", json_body=PRODUCT)
        self.rest.on("PUT", "/products/cached/p1", status=500, text="boom")
        await self.client.queries.cached(id="p1")
        with self.assertRaises(RestError):
            await self.client.mutations.update_cached(id="p1", input=ProductIn(name="x"))
        await self.client.queries.cached(id="p1")
        self.assertEqual(len([c for c in self.rest.calls if c.method == "GET"]), 1)

    async def test_stale_if_offline_serves_stale_data_on_a_transport_failure_only(self) -> None:
        self.rest.on("GET", "/products/offline/p1", json_body=PRODUCT)
        await self.client.queries.cached_offline(id="p1")
        await asyncio.sleep(1.1)
        self.rest.fail_transport = True
        self.assertEqual((await self.client.queries.cached_offline(id="p1")).id, "p1")
        self.rest.fail_transport = False
        self.rest.on("GET", "/products/offline/p1", status=500, text="down")
        with self.assertRaises(RestError):
            await self.client.queries.cached_offline(id="p1")


class MixedAndDownloads(RestMockCase):
    async def test_graphql_and_rest_share_one_client(self) -> None:
        self.rest.on("GET", "/products/count", json_body=3)
        self.assertEqual((await self.client.queries.ping()).ping, "pong")
        self.assertEqual(await self.client.queries.count(), 3)

    async def test_download_metadata_comes_from_the_response(self) -> None:
        self.rest.on(
            "GET",
            "/products/p1/export",
            text="abcdef",
            headers={"Content-Type": "text/csv", "Content-Length": "6", "Content-Disposition": 'attachment; filename="p 1.csv"'},
        )
        received = []
        download = await self.client.queries.export(id="p1", on_receive_progress=lambda r, t: received.append(r * 100 + t))
        self.assertEqual((download.filename, download.content_type, download.length), ("p 1.csv", "text/csv", 6))
        self.assertEqual(self.rest.last.headers["Accept"], "*/*")
        self.assertEqual(await download.bytes(), b"abcdef")
        self.assertEqual(received[-1], 606)

    async def test_rfc5987_filename_is_decoded(self) -> None:
        self.rest.on("GET", "/products/p1/export", text="x", headers={"Content-Disposition": "attachment; filename*=UTF-8''p%201%C3%A9.csv"})
        self.assertEqual((await self.client.queries.export(id="p1")).filename, "p 1é.csv")

    async def test_nullable_download_null_on_204_and_non_null_is_an_error(self) -> None:
        self.rest.on("GET", "/products/p1/maybe", status=204)
        self.assertIsNone(await self.client.queries.maybe_export(id="p1"))
        self.rest.on("GET", "/products/p1/export", status=204)
        with self.assertRaisesRegex(ValueError, "Empty REST response"):
            await self.client.queries.export(id="p1")

    async def test_non_2xx_download_raises_rest_error(self) -> None:
        self.rest.on("GET", "/products/p1/export", status=500, text="x")
        with self.assertRaises(RestError):
            await self.client.queries.export(id="p1")
