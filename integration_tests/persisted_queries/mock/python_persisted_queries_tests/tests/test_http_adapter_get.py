import asyncio
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qsl, urlsplit

from generated import GraphLinkClient, GraphLinkGetNotSupported

from . import fixtures as fx
from .apq_server import ApqServer


class RequestLog:
    def __init__(self, method: str, query: Dict[str, str], authorization: Optional[str]) -> None:
        self.method = method
        self.query = query
        self.authorization = authorization


def make_handler(server: ApqServer, seen: List[RequestLog]) -> type:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args: Any) -> None:
            return None

        def _reply(self, status: int, body: str = "") -> None:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode("utf-8"))

        def do_GET(self) -> None:
            params = dict(parse_qsl(urlsplit(self.path).query))
            seen.append(RequestLog("GET", params, self.headers.get("authorization")))
            payload = json.dumps(
                {
                    **({"operationName": params["operationName"]} if "operationName" in params else {}),
                    "variables": json.loads(params["variables"]) if "variables" in params else {},
                    "extensions": json.loads(params["extensions"]),
                }
            )
            try:
                body = asyncio.run(server.get(payload))
            except GraphLinkGetNotSupported:
                self._reply(405)
                return
            self._reply(200, body)

        def do_POST(self) -> None:
            seen.append(RequestLog("POST", {}, self.headers.get("authorization")))
            length = int(self.headers.get("content-length", "0"))
            self._reply(200, asyncio.run(server.call(self.rfile.read(length).decode("utf-8"))))

    return Handler


class HttpAdapterGetTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.server = ApqServer()
        self.server.respond_to("persistedLongQuery", {"getUser": fx.USER_ALICE})
        self.seen: List[RequestLog] = []
        self.http = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.server, self.seen))
        threading.Thread(target=lambda: self.http.serve_forever(poll_interval=0.01), daemon=True).start()
        port = self.http.server_address[1]

        async def headers() -> Dict[str, str]:
            return {"authorization": "Bearer token"}

        self.client = GraphLinkClient.with_http(
            url=f"http://127.0.0.1:{port}/graphql",
            ws_url=f"ws://127.0.0.1:{port}/graphql",
            headers_provider=headers,
        )

    async def asyncTearDown(self) -> None:
        self.http.shutdown()
        self.http.server_close()

    def methods(self) -> List[str]:
        return [r.method for r in self.seen]

    async def test_cold_query_is_get_then_post(self) -> None:
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(self.methods(), ["GET", "POST"])

    async def test_get_carries_operation_variables_and_hash(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        query = self.seen[0].query
        self.assertEqual(set(query), {"operationName", "variables", "extensions"})
        self.assertEqual(query["operationName"], "persistedLongQuery")
        self.assertEqual(json.loads(query["variables"]), {"id": "user-1"})
        self.assertEqual(json.loads(query["extensions"])["persistedQuery"]["version"], 1)

    async def test_warm_query_is_a_single_get(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.seen.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(self.methods(), ["GET"])

    async def test_headers_provider_applies_to_get(self) -> None:
        await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(self.seen[0].authorization, "Bearer token")

    async def test_405_falls_back_to_post_and_remembers(self) -> None:
        self.server.get_supported = False
        res = await self.client.queries.persisted_long_query(id="user-1")
        self.assertEqual(res.get_user.name, "Alice Smith")
        self.assertEqual(self.methods(), ["GET", "POST", "POST"])
        self.seen.clear()
        await self.client.queries.persisted_long_query(id="user-2")
        self.assertEqual(self.methods(), ["POST"])

    async def test_plus_and_space_in_variables_survive_encoding(self) -> None:
        await self.client.queries.persisted_long_query(id="a+b c&d=e")
        self.assertEqual(json.loads(self.seen[0].query["variables"]), {"id": "a+b c&d=e"})


if __name__ == "__main__":
    unittest.main()
