import asyncio
import unittest

from generated import AddressInput, CreateUserInput, GraphLinkClient, UserStatus

from . import fixtures as fx
from .mock_adapter import MockAdapter, MockWebSocketAdapter

MINIMAL_INPUT = CreateUserInput(
    name="Alice Smith",
    email="alice@test.com",
    status=UserStatus.ACTIVE,
    address=AddressInput(street="123 Main St", city="Springfield", country="US"),
)


class CacheTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.client = GraphLinkClient(adapter=self.adapter.call, ws_adapter=MockWebSocketAdapter())

    async def test_cache_hit(self) -> None:
        self.adapter.register_data("getCachedUser", {"getCachedUser": fx.USER_ALICE})
        first = await self.client.queries.get_cached_user(id="user-1")
        second = await self.client.queries.get_cached_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 1)
        self.assertEqual(second.get_cached_user.id, first.get_cached_user.id)
        self.assertEqual(second.get_cached_user.name, "Alice Smith")

    async def test_different_args_cached_independently(self) -> None:
        self.adapter.register_data("getCachedUser", {"getCachedUser": fx.USER_ALICE})
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_user(id="user-2")
        await self.client.queries.get_cached_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 2)

    async def test_tag_invalidation(self) -> None:
        self.adapter.register_data("getCachedUser", {"getCachedUser": fx.USER_ALICE})
        self.adapter.register_data("listCachedUsers", {"listCachedUsers": [fx.USER_ALICE]})
        self.adapter.register_data("createCachedUser", {"createCachedUser": fx.USER_ALICE})
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 1)
        await self.client.mutations.create_cached_user(input=MINIMAL_INPUT)
        await self.client.queries.get_cached_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 3)

        await self.client.queries.list_cached_users()
        await self.client.queries.list_cached_users()
        self.assertEqual(self.adapter.call_count, 4)
        await self.client.mutations.create_cached_user(input=MINIMAL_INPUT)
        await self.client.queries.list_cached_users()
        self.assertEqual(self.adapter.call_count, 6)

    async def test_multi_tag_invalidation(self) -> None:
        self.adapter.register_data("getCachedUser", {"getCachedUser": fx.USER_ALICE})
        self.adapter.register_data("getCachedPost", {"getCachedPost": fx.POST})
        self.adapter.register_data("transferPost", {"transferPost": fx.POST})
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_post(id="post-1")
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_post(id="post-1")
        self.assertEqual(self.adapter.call_count, 2)
        await self.client.mutations.transfer_post(post_id="post-1", new_author_id="user-2")
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_post(id="post-1")
        self.assertEqual(self.adapter.call_count, 5)

    async def test_untagged_query_survives_invalidation(self) -> None:
        self.adapter.register_data("getCachedConfig", {"getCachedConfig": fx.ALL_SCALARS_NULL})
        self.adapter.register_data("transferPost", {"transferPost": fx.POST})
        await self.client.queries.get_cached_config()
        await self.client.mutations.transfer_post(post_id="post-1", new_author_id="user-2")
        await self.client.queries.get_cached_config()
        self.assertEqual(self.adapter.call_count, 2)

    async def test_invalidate_all(self) -> None:
        self.adapter.register_data("getCachedUser", {"getCachedUser": fx.USER_ALICE})
        self.adapter.register_data("getCachedPost", {"getCachedPost": fx.POST})
        self.adapter.register_data("getCachedConfig", {"getCachedConfig": fx.ALL_SCALARS_NULL})
        self.adapter.register_data("resetAll", {"resetAll": True})
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_post(id="post-1")
        await self.client.queries.get_cached_config()
        res = await self.client.mutations.reset_all()
        self.assertIs(res.reset_all, True)
        await self.client.queries.get_cached_user(id="user-1")
        await self.client.queries.get_cached_post(id="post-1")
        await self.client.queries.get_cached_config()
        self.assertEqual(self.adapter.call_count, 7)

    async def test_ttl_expiry(self) -> None:
        self.adapter.register_data("getStaleUser", {"getStaleUser": fx.USER_ALICE})
        await self.client.queries.get_stale_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 1)
        await asyncio.sleep(2)
        await self.client.queries.get_stale_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 2)

    async def test_stale_if_offline_returns_stale(self) -> None:
        self.adapter.register_data("getStaleUser", {"getStaleUser": fx.USER_ALICE})
        await self.client.queries.get_stale_user(id="user-1")
        await asyncio.sleep(2)
        self.adapter.simulate_failure = True
        res = await self.client.queries.get_stale_user(id="user-1")
        self.assertEqual(res.get_stale_user.name, "Alice Smith")
        self.assertEqual(self.adapter.call_count, 1)

    async def test_stale_if_offline_without_stale_value_raises(self) -> None:
        self.adapter.simulate_failure = True
        with self.assertRaises(Exception):
            await self.client.queries.get_stale_user(id="user-1")

    async def test_no_cache_always_hits_adapter(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        await self.client.queries.get_user(id="user-1")
        await self.client.queries.get_user(id="user-1")
        self.assertEqual(self.adapter.call_count, 2)


if __name__ == "__main__":
    unittest.main()
