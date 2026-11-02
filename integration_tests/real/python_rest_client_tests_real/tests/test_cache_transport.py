import asyncio

from generated import InMemoryGraphLinkCacheStore, RestError

from .support import RestTestCase, SERVER_URL, pattern, part, query_value, upload_of, form_value
from .support import Echo


class CountingStore(InMemoryGraphLinkCacheStore):
    def __init__(self) -> None:
        super().__init__()
        self.sets = 0

    async def set(self, key: str, value: str) -> None:
        self.sets += 1
        await super().set(key, value)


DEAD = "http://127.0.0.1:1"


class CacheTestCase(RestTestCase):
    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.store = InMemoryGraphLinkCacheStore()
        self.client = self.new_client(store=self.store)


class CacheQueries(CacheTestCase):
    async def test_second_call_is_served_from_the_cache(self) -> None:
        first = await self.client.queries.counter(name="a")
        second = await self.client.queries.counter(name="a")
        self.assertEqual((first.n, second.n), (1, 1))
        self.assertEqual((await self.client.queries.counter_uncached(name="a")).n, 2)

    async def test_different_arguments_are_different_entries(self) -> None:
        self.assertEqual((await self.client.queries.counter(name="a")).n, 1)
        self.assertEqual((await self.client.queries.counter(name="b")).n, 1)
        self.assertEqual((await self.client.queries.counter(name="a")).n, 1)

    async def test_uncached_and_no_cache_are_never_cached(self) -> None:
        self.assertEqual((await self.client.queries.counter_uncached(name="u")).n, 1)
        self.assertEqual((await self.client.queries.counter_uncached(name="u")).n, 2)
        self.assertEqual((await self.client.queries.counter_no_cache(name="u")).n, 3)
        self.assertEqual((await self.client.queries.counter_no_cache(name="u")).n, 4)

    async def test_entry_expires_after_its_ttl(self) -> None:
        self.assertEqual((await self.client.queries.counter_short(name="s")).n, 1)
        self.assertEqual((await self.client.queries.counter_short(name="s")).n, 1)
        await asyncio.sleep(1.3)
        self.assertEqual((await self.client.queries.counter_short(name="s")).n, 2)

    async def test_cache_is_shared_by_clients_using_the_same_store(self) -> None:
        await self.client.queries.counter(name="shared")
        other = self.new_client(store=self.store)
        self.assertEqual((await other.queries.counter(name="shared")).n, 1)
        self.assertEqual((await self.new_client().queries.counter(name="shared")).n, 2)


class CacheInvalidation(CacheTestCase):
    async def test_invalidates_entries_holding_the_tag(self) -> None:
        self.assertEqual((await self.client.queries.counter(name="c")).n, 1)
        await self.client.mutations.bump(name="c")
        self.assertEqual((await self.client.queries.counter(name="c")).n, 102)

    async def test_leaves_entries_with_other_tags_alone(self) -> None:
        self.assertEqual((await self.client.queries.counter_other(name="o")).n, 1)
        self.assertEqual((await self.client.queries.counter(name="o")).n, 2)
        await self.client.mutations.bump(name="o")
        self.assertEqual((await self.client.queries.counter_other(name="o")).n, 1)
        self.assertGreater((await self.client.queries.counter(name="o")).n, 100)

    async def test_all_clears_everything(self) -> None:
        await self.client.queries.counter(name="x")
        await self.client.queries.counter_other(name="x")
        await self.client.mutations.reset_all(name="x")
        self.assertEqual((await self.client.queries.counter(name="x")).n, 1)
        self.assertEqual((await self.client.queries.counter_other(name="x")).n, 2)

    async def test_failed_mutation_does_not_invalidate_but_204_does(self) -> None:
        await self.client.queries.counter(name="f")
        with self.assertRaises(RestError):
            await self.client.mutations.bump_fails(code=500)
        self.assertEqual((await self.client.queries.counter(name="f")).n, 1)
        await self.client.mutations.bump_fails(code=204)
        self.assertEqual((await self.client.queries.counter(name="f")).n, 2)


class CacheFailures(CacheTestCase):
    async def test_error_response_is_not_cached(self) -> None:
        writes = CountingStore()
        client = self.new_client(store=writes)
        with self.assertRaises(RestError):
            await client.queries.cached_status(code=500)
        self.assertEqual(writes.sets, 0)
        self.assertEqual((await client.queries.cached_status(code=200)).id, "p1")
        self.assertEqual(writes.sets, 1)

    async def test_response_that_fails_to_decode_is_not_cached(self) -> None:
        writes = CountingStore()
        client = self.new_client(store=writes)
        for _ in range(2):
            with self.assertRaises(Exception):
                await client.queries.cached_bad()
        self.assertEqual(writes.sets, 0)

    async def test_stale_if_offline_serves_the_expired_entry_on_transport_failure(self) -> None:
        await self.client.queries.counter_offline(name="off")
        await asyncio.sleep(1.3)
        offline = self.new_client(base_url=DEAD, store=self.store)
        self.assertEqual((await offline.queries.counter_offline(name="off")).n, 1)

    async def test_without_stale_if_offline_a_transport_failure_surfaces(self) -> None:
        await self.client.queries.counter_short(name="off2")
        await asyncio.sleep(1.3)
        offline = self.new_client(base_url=DEAD, store=self.store)
        with self.assertRaises(Exception) as caught:
            await offline.queries.counter_short(name="off2")
        self.assertNotIsInstance(caught.exception, RestError)

    async def test_fresh_entry_is_served_even_when_unreachable(self) -> None:
        await self.client.queries.counter(name="fresh")
        offline = self.new_client(base_url=DEAD, store=self.store)
        self.assertEqual((await offline.queries.counter(name="fresh")).n, 1)

    async def test_nothing_cached_and_unreachable_is_a_transport_error(self) -> None:
        offline = self.new_client(base_url=DEAD, store=self.store)
        with self.assertRaises(Exception) as caught:
            await offline.queries.counter(name="never")
        self.assertNotIsInstance(caught.exception, RestError)


class Transport(RestTestCase):
    async def test_path_prefix_trailing_slash_and_bare_base_url(self) -> None:
        e = await self.new_client(base_url=f"{SERVER_URL}/api").queries.e_scalars(id="p")
        self.assertEqual(e.path, "/api/echo/scalars/p")
        e = await self.new_client(base_url=f"{SERVER_URL}/api/").queries.e_scalars(id="p")
        self.assertEqual(e.path, "/api/echo/scalars/p")
        e = await self.new_client(base_url=f"{SERVER_URL}/").queries.e_scalars(id="p")
        self.assertEqual(e.path, "/echo/scalars/p")

    async def test_unreachable_server_is_not_a_rest_error_and_the_client_keeps_working(self) -> None:
        dead = self.new_client(base_url=DEAD)
        with self.assertRaises(Exception) as caught:
            await dead.queries.e_accept()
        self.assertNotIsInstance(caught.exception, RestError)
        self.assertEqual((await self.client.queries.e_accept()).method, "GET")

    async def test_concurrent_requests_do_not_mix_their_data(self) -> None:
        results = await asyncio.gather(*[self.client.queries.e_scalars(id=f"id{i}", i=i) for i in range(60)])
        for i, e in enumerate(results):
            self.assertEqual(e.path, f"/echo/scalars/id{i}")
            self.assertEqual(query_value(e, "i"), str(i))

    async def test_mixed_request_kinds_in_parallel(self) -> None:
        from generated import ProductIn

        async def blob() -> bytes:
            return await (await self.client.queries.blob(size=2000)).bytes()

        out = await asyncio.gather(
            self.client.queries.e_accept(),
            self.client.mutations.e_json(body=ProductIn(name="x")),
            self.client.mutations.e_form(name="f"),
            self.client.mutations.e_multipart(title="t"),
            self.client.mutations.e_raw(file=upload_of(pattern(1000))),
            blob(),
        )
        self.assertEqual(out[0].method, "GET")
        self.assertRegex(out[1].content_type, r"^application/json")
        self.assertEqual(form_value(out[2], "name"), "f")
        self.assertEqual(part(out[3], "title").text, "t")
        self.assertEqual(out[4].body_size, 1000)
        self.assertEqual(len(out[5]), 2000)
