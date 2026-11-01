import json
import unittest
import urllib.request
from typing import Any, Dict

from generated import AddressInput, CreateUserInput, GraphLinkClient, UserStatus

PORT = 9997
GRAPHQL = f"http://localhost:{PORT}/graphql"
WS = f"ws://localhost:{PORT}/graphql"

NEW_USER = CreateUserInput(
    name="Persisted Pat",
    email="pat@test.com",
    status=UserStatus.ACTIVE,
    address=AddressInput(street="s", city="c", country="x"),
)


def control(method: str, path: str) -> Dict[str, Any]:
    request = urllib.request.Request(f"http://localhost:{PORT}/test/apq{path}", method=method)
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read())


def stats() -> Dict[str, Any]:
    return control("GET", "")


def new_client() -> GraphLinkClient:
    return GraphLinkClient.with_http(url=GRAPHQL, ws_url=WS)


class PersistedQueriesRealTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        control("POST", "/reset")
        self.client = new_client()


class LongQueryTest(PersistedQueriesRealTest):
    async def test_registered_on_first_call(self) -> None:
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        current = stats()
        self.assertEqual((current["misses"], current["registrations"], current["stored"], current["gets"]), (1, 1, 1, 1))

    async def test_single_get_hit_once_registered(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        current = stats()
        self.assertEqual((current["hits"], current["registrations"], current["gets"]), (1, 1, 2))

    async def test_fresh_client_reuses_stored_query(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        res = await new_client().queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        current = stats()
        self.assertEqual((current["hits"], current["registrations"]), (1, 1))

    async def test_registered_again_after_eviction(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        control("POST", "/evict")
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        current = stats()
        self.assertEqual((current["registrations"], current["stored"]), (2, 1))

    async def test_server_without_apq_support_still_works(self) -> None:
        control("POST", "/supported/false")
        first = await self.client.queries.persisted_long_query(id="user-1")
        second = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual((first.get_user.name, second.get_user.name), ("Alice Smith", "Alice Smith"))
        current = stats()
        self.assertEqual((current["stored"], current["gets"]), (0, 1))


class MutationTest(PersistedQueriesRealTest):
    async def test_registered_and_posted_never_get(self) -> None:
        res = await self.client.mutations.persisted_long_mutation(input=NEW_USER)
        self.assertEqual(res.create_user.name, "Persisted Pat")
        current = stats()
        self.assertEqual((current["registrations"], current["gets"]), (1, 0))

    async def test_hash_only_post_once_registered(self) -> None:
        await self.client.mutations.persisted_long_mutation(input=NEW_USER)
        res = await self.client.mutations.persisted_long_mutation(input=NEW_USER)
        self.assertEqual(res.create_user.email, "pat@test.com")
        current = stats()
        self.assertEqual((current["hits"], current["registrations"], current["gets"]), (1, 1, 0))


class ShortQueryTest(PersistedQueriesRealTest):
    async def test_short_query_bypasses_persisted_queries(self) -> None:
        res = await self.client.queries.persisted_short_query()
        self.assertTrue(res.list_users)
        current = stats()
        self.assertEqual((current["hits"], current["misses"], current["registrations"], current["gets"]), (0, 0, 0, 0))


if __name__ == "__main__":
    unittest.main()
