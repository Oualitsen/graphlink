import asyncio

from generated import ProductIn, RestError, Status

from .support import RestTestCase, pattern, sha256_of, upload_of


class Download(RestTestCase):
    async def test_metadata_comes_from_headers_and_bytes_are_exact(self) -> None:
        d = await self.client.queries.blob(size=100000)
        self.assertEqual(d.filename, "blob-100000.bin")
        self.assertRegex(d.content_type, r"^application/octet-stream")
        self.assertEqual(d.length, 100000)
        self.assertEqual(await d.bytes(), pattern(100000))

    async def test_multi_megabyte_download_is_streamed_and_intact(self) -> None:
        size = 8 * 1024 * 1024
        d = await self.client.queries.blob(size=size)
        chunks = []
        async for chunk in d.stream:
            chunks.append(chunk)
        self.assertGreater(len(chunks), 1)
        self.assertEqual(sha256_of(b"".join(chunks)), sha256_of(pattern(size)))

    async def test_progress_ends_at_the_total(self) -> None:
        reports = []
        d = await self.client.queries.blob(size=500000, on_receive_progress=lambda r, t: reports.append((r, t)))
        await d.bytes()
        self.assertEqual(reports[-1], (500000, 500000))
        self.assertEqual([r[0] for r in reports], sorted(r[0] for r in reports))

    async def test_empty_download(self) -> None:
        d = await self.client.queries.blob(size=0)
        self.assertEqual(await d.bytes(), b"")

    async def test_missing_resource_is_a_rest_error(self) -> None:
        with self.assertRaises(RestError) as caught:
            await self.client.queries.avatar(id="p1")
        self.assertEqual(caught.exception.status, 404)

    async def test_upload_and_matching_download_round_trip(self) -> None:
        data = pattern(70000)
        await self.client.mutations.upload_avatar(id="p1", file=upload_of(data, mime_type="image/png"))
        d = await self.client.queries.avatar(id="p1")
        self.assertRegex(d.content_type, r"^image/png")
        self.assertEqual(d.filename, "p1.png")
        self.assertEqual(await d.bytes(), data)

    async def test_nullable_download_is_null_on_204_and_present_afterwards(self) -> None:
        self.assertIsNone(await self.client.queries.avatar_or_empty(id="p1"))
        await self.client.mutations.upload_avatar(id="p1", file=upload_of(pattern(10)))
        self.assertEqual(await (await self.client.queries.avatar_or_empty(id="p1")).bytes(), pattern(10))

    async def test_several_downloads_can_be_open_at_once(self) -> None:
        downloads = await asyncio.gather(*[self.client.queries.blob(size=i * 1000) for i in range(1, 6)])
        data = await asyncio.gather(*[d.bytes() for d in downloads])
        self.assertEqual([len(b) for b in data], [1000, 2000, 3000, 4000, 5000])


class CrudFlow(RestTestCase):
    async def test_product_lifecycle(self) -> None:
        created = await self.client.mutations.create_product(input=ProductIn(name="Lamp", price=30.0, tags=["home"]))
        self.assertEqual(created.name, "Lamp")
        self.assertEqual(created.status, Status.ACTIVE)
        self.assertEqual((await self.client.queries.product(id=created.id)).price, 30)
        from generated import Filter

        by_tag = await self.client.queries.products(filter=Filter(tag="home"))
        self.assertEqual([p.id for p in by_tag], [created.id])
        by_ids = await self.client.queries.products(ids=["p1", created.id])
        self.assertEqual({p.id for p in by_ids}, {"p1", created.id})
        patched = await self.client.mutations.patch_product(id=created.id, input=ProductIn(name="Lamp 2", price=35.0))
        self.assertEqual((patched.name, patched.price), ("Lamp 2", 35))
        renamed = await self.client.mutations.rename_product(id=created.id, name="Lamp 3", note="n")
        self.assertEqual((renamed.name, renamed.tags), ("Lamp 3", ["n"]))
        gallery = await self.client.mutations.gallery(
            id=created.id,
            title="Gallery é",
            files=[upload_of(pattern(100), "a.png"), upload_of(pattern(200), "b.png")],
        )
        self.assertEqual((gallery.name, gallery.tags), ("Gallery é", ["a.png", "b.png"]))
        replaced = await self.client.mutations.replace_product(id=created.id, input=ProductIn(name="Final"))
        self.assertEqual(replaced.name, "Final")
        await self.client.mutations.delete_product(id=created.id)
        with self.assertRaises(RestError) as caught:
            await self.client.queries.product(id=created.id)
        self.assertEqual(caught.exception.status, 404)

    async def test_void_succeeds_on_204_and_fails_on_a_missing_resource(self) -> None:
        await self.client.mutations.delete_product(id="p2")
        with self.assertRaises(RestError) as caught:
            await self.client.mutations.delete_product(id="p2")
        self.assertEqual(caught.exception.status, 404)

    async def test_same_client_serves_many_concurrent_calls(self) -> None:
        results = await asyncio.gather(*[self.client.mutations.create_product(input=ProductIn(name=f"item-{i}")) for i in range(40)])
        self.assertEqual(len({p.name for p in results}), 40)
        self.assertEqual(len({p.id for p in results}), 40)
        self.assertEqual(len(await self.client.queries.products()), 42)

    async def test_products_list_with_no_filters(self) -> None:
        self.assertEqual([p.id for p in await self.client.queries.products()], ["p1", "p2"])
