import json
import unittest
from typing import Any, Dict

from generated import AddressInput, CreateUserInput, GraphLinkClient, GraphLinkException, UserStatus

from . import fixtures as fx
from .apq_server import ApqServer, NoWebSocketAdapter, sha256_hex


def hash_of(request: Dict[str, Any]) -> Dict[str, Any]:
    return request["extensions"]["persistedQuery"]


def new_input() -> CreateUserInput:
    return CreateUserInput(
        name="Alice",
        email="a@test.com",
        status=UserStatus.ACTIVE,
        address=AddressInput(street="s", city="c", country="x"),
    )


class RequestFlowTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.server = ApqServer()
        self.client = GraphLinkClient(
            adapter=self.server.call, get_adapter=self.server.get, ws_adapter=NoWebSocketAdapter()
        )


class LongQueryFlowTest(RequestFlowTest):
    def setUp(self) -> None:
        super().setUp()
        self.server.respond_to("persistedLongQuery", {"getUser": fx.USER_ALICE})

    async def test_hash_first_then_registered_by_retry(self) -> None:
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(len(self.server.requests), 2)
        hash_only, retry = self.server.requests
        self.assertNotIn("query", hash_only)
        self.assertEqual(hash_only["operationName"], "persistedLongQuery")
        self.assertEqual(hash_only["variables"], {"id": "user-1"})
        self.assertIsInstance(retry["query"], str)
        self.assertEqual(retry["variables"], {"id": "user-1"})

    async def test_hash_is_sha256_of_the_retry_query(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        hash_only, retry = self.server.requests
        self.assertEqual(hash_of(retry), {"version": 1, "sha256Hash": sha256_hex(retry["query"])})
        self.assertEqual(hash_of(hash_only), hash_of(retry))

    async def test_single_request_once_the_server_knows_it(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.server.requests.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(len(self.server.requests), 1)
        self.assertTrue(self.server.is_hash_only(self.server.requests[0]))
        self.assertEqual(self.server.requests[0]["variables"], {"id": "user-2"})

    async def test_registered_again_after_eviction(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.server.evict()
        self.server.requests.clear()
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(len(self.server.requests), 2)
        self.assertTrue(self.server.is_hash_only(self.server.requests[0]))
        self.assertIn("query", self.server.requests[1])

    async def test_missing_hash_reported_only_by_code_still_retries(self) -> None:
        self.server.not_found_message = "Unknown query"
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(len(self.server.requests), 2)
        self.assertIn("query", self.server.requests[1])


class OtherOperationsFlowTest(RequestFlowTest):
    async def test_short_query_is_sent_in_full(self) -> None:
        self.server.respond_to("persistedShortQuery", {"listUsers": []})
        await self.client.queries.persisted_short_query()
        self.assertEqual(len(self.server.requests), 1)
        self.assertIn("listUsers", self.server.requests[0]["query"])
        self.assertNotIn("extensions", self.server.requests[0])

    async def test_long_mutation_uses_hash_then_register(self) -> None:
        self.server.respond_to("persistedLongMutation", {"createUser": fx.USER_ALICE})
        res = await self.client.mutations.persisted_long_mutation(input=new_input())
        self.assertEqual(res.create_user.name, "Alice Smith")
        self.assertEqual(len(self.server.requests), 2)
        self.assertTrue(self.server.is_hash_only(self.server.requests[0]))
        self.assertIn("query", self.server.requests[1])

    async def test_cached_query_hashes_the_assembled_request(self) -> None:
        self.server.respond_to("fetchCachedPair", {"user": fx.USER_ALICE, "post": fx.POST})
        res = await self.client.queries.fetch_cached_pair(user_id="user-1", post_id="post-1")
        self.assertEqual(res.user.name, "Alice Smith")
        retry = self.server.requests[1]
        self.assertEqual(hash_of(retry)["sha256Hash"], sha256_hex(retry["query"]))
        self.assertIn("getCachedUser", retry["query"])


class ServerWithoutApqTest(RequestFlowTest):
    def setUp(self) -> None:
        super().setUp()
        self.server.supported = False
        self.server.respond_to("persistedLongQuery", {"getUser": fx.USER_ALICE})

    async def test_full_query_right_after_first_refusal(self) -> None:
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(len(self.server.requests), 2)
        self.assertIn("query", self.server.requests[1])
        self.assertNotIn("extensions", self.server.requests[1])

    async def test_not_asked_about_hashes_again(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.server.requests.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(len(self.server.requests), 1)
        self.assertIn("query", self.server.requests[0])
        self.assertNotIn("extensions", self.server.requests[0])


class NonPersistedErrorsTest(RequestFlowTest):
    async def test_graphql_error_is_not_retried(self) -> None:
        self.server.respond_to("persistedLongQuery", {"getUser": fx.USER_ALICE})
        await self.client.queries.persisted_long_query(id="user-1")
        self.server.requests.clear()
        self.server.respond_with_errors("persistedLongQuery", [{"message": "boom"}])
        with self.assertRaises(GraphLinkException):
            await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(len(self.server.requests), 1)

    async def test_transport_failure_propagates_without_second_request(self) -> None:
        self.server.respond_to("persistedLongMutation", {"createUser": fx.USER_ALICE})
        self.server.fail_with = Exception("timeout")
        with self.assertRaises(Exception) as raised:
            await self.client.mutations.persisted_long_mutation(input=new_input())
        self.assertEqual(str(raised.exception), "timeout")
        self.assertEqual(self.server.methods, ["POST"])


class GetAdapterTest(RequestFlowTest):
    def setUp(self) -> None:
        super().setUp()
        self.server.respond_to("persistedLongQuery", {"getUser": fx.USER_ALICE})
        self.server.respond_to("persistedShortQuery", {"listUsers": []})
        self.server.respond_to("persistedLongMutation", {"createUser": fx.USER_ALICE})

    async def test_get_first_then_post_registers(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(self.server.methods, ["GET", "POST"])
        self.assertTrue(self.server.is_hash_only(self.server.requests[0]))
        self.assertIn("query", self.server.requests[1])
        self.assertEqual(set(self.server.requests[0]), {"operationName", "variables", "extensions"})

    async def test_single_get_once_known(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.server.methods.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(self.server.methods, ["GET"])

    async def test_requests_that_never_use_get(self) -> None:
        await self.client.queries.persisted_short_query()
        self.assertEqual(self.server.methods, ["POST"])
        self.server.methods.clear()
        await self.client.mutations.persisted_long_mutation(input=new_input())
        self.assertEqual(self.server.methods, ["POST", "POST"])
        self.assertTrue(self.server.is_hash_only(self.server.requests[-2]))

    async def test_server_refusing_get_falls_back_to_post_and_remembers(self) -> None:
        self.server.get_supported = False
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(self.server.methods, ["GET", "POST", "POST"])
        self.assertEqual(len(self.server.requests), 2)
        self.server.methods.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(self.server.methods, ["POST"])

    async def test_server_without_apq_gets_full_query_by_post(self) -> None:
        self.server.supported = False
        await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(self.server.methods, ["GET", "POST"])
        self.assertNotIn("extensions", self.server.requests[1])

    async def test_other_get_failures_propagate(self) -> None:
        self.server.get_fail_with = Exception("network down")
        with self.assertRaises(Exception):
            await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(self.server.methods, ["GET"])


class HashTest(RequestFlowTest):
    async def test_reference_vectors(self) -> None:
        self.assertEqual(
            self.client.queries.gl_hash("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        self.assertEqual(
            self.client.queries.gl_hash(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        self.assertEqual(
            self.client.queries.gl_hash("query GetUser($id: ID!){getUser(id:$id){id name}}"),
            "76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc",
        )

    async def test_repeatable_and_shared(self) -> None:
        first = self.client.queries.gl_hash("query A{a}")
        self.assertEqual(self.client.queries.gl_hash("query A{a}"), first)
        self.assertNotEqual(self.client.queries.gl_hash("query B{b}"), first)
        self.assertEqual(self.client.mutations.gl_hash("abc"), self.client.queries.gl_hash("abc"))


if __name__ == "__main__":
    unittest.main()
