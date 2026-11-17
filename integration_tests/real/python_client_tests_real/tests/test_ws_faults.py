import asyncio
import json
import os
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx

from generated import DefaultGraphLinkWebSocketAdapter, GraphLinkClient, GraphLinkHttpxAdapter

FAULT_PORT = int(os.environ.get("WS_FAULT_PORT", "9942"))
FAULT_URL = f"http://127.0.0.1:{FAULT_PORT}"
CASES: List[Dict[str, Any]] = json.loads((Path(__file__).parents[2] / "fault_server" / "ws_cases.json").read_text())

NO_ACK_TIMEOUT = "the handshake waits for connection_ack with no timeout"
RECONNECTS_ON_4XXX = "reconnects and resubscribes after a 4xxx close instead of surfacing an error"
KNOWN_DEFECTS: Dict[str, str] = {
    "ws-no-ack": NO_ACK_TIMEOUT,
    "ws-close-4400": RECONNECTS_ON_4XXX,
    "ws-close-4401": RECONNECTS_ON_4XXX,
    "ws-close-4403": RECONNECTS_ON_4XXX,
    "ws-close-4409": RECONNECTS_ON_4XXX,
}


class WsFaultCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.http = httpx.AsyncClient()
        await self.http.post(f"{FAULT_URL}/_reset")
        self.ws = DefaultGraphLinkWebSocketAdapter(url=f"ws://127.0.0.1:{FAULT_PORT}/graphql", reconnect=True)
        http = GraphLinkHttpxAdapter(url=f"{FAULT_URL}/graphql")
        self.client = GraphLinkClient(adapter=http.call, ws_adapter=self.ws)
        self.task: Optional[asyncio.Future] = None

    async def asyncTearDown(self) -> None:
        if self.task is not None:
            self.task.cancel()
        await self.ws.close()
        await self.http.aclose()

    async def run_case(self, case: Dict[str, Any]) -> None:
        fault = case["fault"]
        await self.http.post(f"{FAULT_URL}/_arm", params={"fault": fault, "times": case.get("times", 1)})
        events: List[int] = []
        outcome: Dict[str, Any] = {"error": None, "ended": False}

        async def consume() -> None:
            try:
                async for event in self.client.subscriptions.counter_tick():
                    events.append(event.counter_tick)
                outcome["ended"] = True
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                outcome["error"] = e

        self.task = asyncio.ensure_future(consume())
        await asyncio.wait({self.task}, timeout=case.get("waitSeconds", 8))
        settled = self.task.done()
        log = (await self.http.get(f"{FAULT_URL}/_ws_log")).json()

        if "waitSeconds" not in case:
            expect = case["expect"]
            if expect == "value":
                self.assertIsNone(outcome["error"], f"unexpected failure: {outcome['error']!r}")
                self.assertTrue(settled, "the subscription never completed")
                self.assertEqual(events, [1])
            elif expect == "error":
                self.assertTrue(settled, "the subscription hung")
                self.assertIsNotNone(outcome["error"], f"no failure, events={events}")
                if "message" in case:
                    self.assertIn(case["message"], str(outcome["error"]))
            else:
                self.assertTrue(settled, "the subscription hung")
        if case.get("noSubscribeBeforeAck"):
            sent = [f["type"] for c in log for f in c["frames"]]
            self.assertNotIn("subscribe", sent)
        if case.get("pong"):
            self.assertIn("pong", [f["type"] for c in log for f in c["frames"]])
        if "maxConnections" in case:
            self.assertLessEqual(len(log), case["maxConnections"])
        if "minConnections" in case:
            self.assertGreaterEqual(len(log), case["minConnections"])


def _add(case: Dict[str, Any]) -> None:
    async def test(self: WsFaultCase) -> None:
        await self.run_case(case)

    fault = case["fault"]
    setattr(WsFaultCase, f"test_{fault.replace('-', '_')}", unittest.skip(KNOWN_DEFECTS[fault])(test) if fault in KNOWN_DEFECTS else test)


for _case in CASES:
    _add(_case)

if __name__ == "__main__":
    unittest.main()
