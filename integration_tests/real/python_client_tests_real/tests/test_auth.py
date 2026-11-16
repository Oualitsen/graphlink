import itertools
import time
import unittest
from typing import Dict

from generated import GraphLinkClient, GraphLinkException

from .real_server import DEFAULT_PORT, http_url, new_client, new_ws_adapter, ws_url
from .test_subscription_streams import drain

_next = itertools.count()


def client_with_headers(provider) -> GraphLinkClient:
    return GraphLinkClient.with_http(
        url=http_url(DEFAULT_PORT), ws_url=ws_url(DEFAULT_PORT), headers_provider=provider, ws_headers_provider=provider
    )


class HeadersTest(unittest.IsolatedAsyncioTestCase):
    async def test_headers_provider_values_reach_the_server(self) -> None:
        async def provider() -> Dict[str, str]:
            return {"X-Test": "v1"}

        client = client_with_headers(provider)
        self.assertEqual((await client.queries.echo_header(name="X-Test")).echo_header, "v1")
        self.assertIsNone((await client.queries.echo_header(name="X-Other")).echo_header)

    async def test_headers_provider_is_evaluated_on_every_request(self) -> None:
        token = {"value": "first"}

        async def provider() -> Dict[str, str]:
            return {"Authorization": f"Bearer {token['value']}"}

        client = client_with_headers(provider)
        self.assertEqual((await client.queries.who_am_i()).who_am_i, "first")
        token["value"] = "second"
        self.assertEqual((await client.queries.who_am_i()).who_am_i, "second")

    async def test_a_missing_token_is_a_graphlink_exception(self) -> None:
        with self.assertRaises(GraphLinkException) as raised:
            await new_client().queries.who_am_i()
        self.assertTrue(raised.exception.errors)


class ConnectionInitTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.adapters = []

    async def asyncTearDown(self) -> None:
        for adapter in self.adapters:
            await adapter.close()

    def client_on_new_ws(self, **adapter_args) -> GraphLinkClient:
        ws = new_ws_adapter(**adapter_args)
        self.adapters.append(ws)
        return new_client(ws_adapter=ws)

    async def test_connection_init_carries_the_token(self) -> None:
        token = f"py-{time.time_ns()}-{next(_next)}"

        async def provider() -> Dict[str, str]:
            return {"Authorization": f"Bearer {token}"}

        events, error = await drain(self.client_on_new_ws(headers_provider=provider).subscriptions.secure_ticks(count=3))
        self.assertIsNone(error)
        self.assertEqual([e.secure_ticks for e in events], [1, 2, 3])
        self.assertEqual((await new_client().queries.secure_tick_starts(token=token)).secure_tick_starts, 1)

    async def test_a_subscription_without_a_token_fails(self) -> None:
        events, error = await drain(self.client_on_new_ws().subscriptions.secure_ticks(count=3))
        self.assertEqual(events, [])
        self.assertIsNotNone(error)
