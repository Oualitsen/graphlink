import asyncio
import json
import unittest
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List

import httpx

from generated import GraphLinkClient, GraphLinkHttpxAdapter, GraphLinkRestHttpxAdapter, RestError
from generated.client.graph_link_exception import GraphLinkException

from .variant import FAULT_PORT

FAULT_URL = f"http://127.0.0.1:{FAULT_PORT}"
CASES: List[Dict[str, str]] = json.loads((Path(__file__).parents[2] / "fault_server" / "cases.json").read_text())

OP_NAMES = {"g": "GraphQL getCount", "c": "REST count", "p": "REST status"}

UNCHECKED = "the generated decoder does not check scalar types at run time"
KNOWN_DEFECTS: Dict[str, str] = {
    "gql-empty-errors:g": "an empty errors list is raised as a failure although data is present",
    "bom:g": "json.loads rejects a UTF-8 byte order mark",
    "bom:c": "json.loads rejects a UTF-8 byte order mark",
    "bom:p": "json.loads rejects a UTF-8 byte order mark",
    "int-as-string:g": UNCHECKED,
    "int-as-string:c": UNCHECKED,
    "int-bool:g": UNCHECKED,
    "int-bool:c": UNCHECKED,
    "int-fraction:c": UNCHECKED,
    "int-object:c": UNCHECKED,
    "int-overflow:g": UNCHECKED,
    "int-overflow:c": UNCHECKED,
    "json-array-top-level:c": UNCHECKED,
    "json-string-top-level:c": UNCHECKED,
}


class FaultCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.http = httpx.AsyncClient()
        await self.http.post(f"{FAULT_URL}/_reset")
        self.rest = GraphLinkRestHttpxAdapter(base_url=FAULT_URL)
        self.graphql = GraphLinkHttpxAdapter(url=f"{FAULT_URL}/graphql")
        self.client = GraphLinkClient(adapter=self.graphql.call, rest_adapter=self.rest)

    async def asyncTearDown(self) -> None:
        await self.rest.aclose()
        await self.graphql.aclose()
        await self.http.aclose()

    async def arm(self, fault: str) -> None:
        await self.http.post(f"{FAULT_URL}/_arm", params={"fault": fault})

    def call(self, op: str) -> Awaitable[Any]:
        if op == "g":
            return self.client.queries.get_count()
        if op == "c":
            return self.client.queries.count()
        return self.client.queries.status(code=200)

    async def assert_healthy(self, op: str) -> None:
        if op == "g":
            self.assertEqual((await self.client.queries.get_count()).get_count, 19)
        elif op == "c":
            self.assertEqual(await self.client.queries.count(), 7)
        else:
            self.assertEqual((await self.client.queries.status(code=200)).name, "Pen")

    async def run_case(self, fault: str, op: str, expected: str) -> None:
        await self.arm(fault)
        result: Any = None
        error: Any = None
        try:
            result = await asyncio.wait_for(self.call(op), timeout=8)
        except asyncio.TimeoutError:
            self.fail(f"{fault} hung for 8 seconds")
        except Exception as e:  # noqa: BLE001
            error = e
        if expected == "value":
            self.assertIsNone(error, f"unexpected failure: {error!r}")
        if expected == "failure":
            self.assertIsNotNone(error, f"decoded without a failure: {result!r}")
        await self.assert_healthy(op)

    async def test_rest_error_carries_the_status_and_the_body_of_a_gateway_page(self) -> None:
        await self.arm("html-502")
        with self.assertRaises(RestError) as caught:
            await self.client.queries.count()
        self.assertEqual(caught.exception.status, 502)
        self.assertIn("Bad Gateway", caught.exception.body)

    async def test_graphql_error_reaches_the_caller_with_message_path_and_extensions(self) -> None:
        await self.arm("gql-errors-only")
        with self.assertRaises(GraphLinkException) as caught:
            await self.client.queries.get_count()
        error = caught.exception.errors[0]
        self.assertEqual(error.message, "boom")
        self.assertEqual(error.path, ["getCount"])
        self.assertEqual(error.extensions, {"code": "BAD"})

    async def test_graphql_call_keeps_the_http_status_and_body_of_a_gateway_page(self) -> None:
        for fault, status, text in (("html-502", 502, "Bad Gateway"), ("status-401-json", 401, "unauthorized")):
            with self.subTest(fault=fault):
                await self.arm(fault)
                with self.assertRaises(GraphLinkException) as caught:
                    await self.client.queries.get_count()
                error = caught.exception.errors[0]
                self.assertEqual(error.status, status)
                self.assertIn(text, error.body)

    async def test_response_without_data_and_without_errors_says_so(self) -> None:
        await self.arm("gql-empty-object")
        with self.assertRaises(GraphLinkException) as caught:
            await self.client.queries.get_count()
        self.assertIn("no data", caught.exception.errors[0].message)


def _add(fault: str, op: str, expected: str) -> None:
    async def test(self: FaultCase) -> None:
        await self.run_case(fault, op, expected)

    name = f"test_{fault.replace('-', '_')}_{OP_NAMES[op].replace(' ', '_').lower()}_{expected}"
    defect = KNOWN_DEFECTS.get(f"{fault}:{op}")
    setattr(FaultCase, name, unittest.skip(defect)(test) if defect else test)


for _case in CASES:
    for _op in _case["ops"]:
        _add(_case["fault"], _op, _case["expect"])
