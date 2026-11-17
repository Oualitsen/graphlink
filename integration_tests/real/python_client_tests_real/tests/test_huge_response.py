import json
import os
import time
import unittest
from pathlib import Path

import httpx

from generated import DefaultGraphLinkWebSocketAdapter, GraphLinkClient, GraphLinkHttpxAdapter

FAULT_PORT = int(os.environ.get("WS_FAULT_PORT", "9942"))
FAULT_URL = f"http://127.0.0.1:{FAULT_PORT}"
USERS: int = json.loads((Path(__file__).parents[2] / "fault_server" / "huge_case.json").read_text())["users"]


class HugeResponse(unittest.IsolatedAsyncioTestCase):
    async def test_a_ten_megabyte_response_is_decoded_without_loss(self) -> None:
        async with httpx.AsyncClient() as control:
            await control.post(f"{FAULT_URL}/_reset")
            await control.post(f"{FAULT_URL}/_arm", params={"fault": "huge-users"})
            ws = DefaultGraphLinkWebSocketAdapter(url=f"ws://127.0.0.1:{FAULT_PORT}/graphql", reconnect=True)
            client = GraphLinkClient(adapter=GraphLinkHttpxAdapter(url=f"{FAULT_URL}/graphql").call, ws_adapter=ws)
            try:
                started = time.monotonic()
                response = await client.queries.fetch_big_users(count=USERS)
                elapsed = time.monotonic() - started

                users = response.big_users
                self.assertEqual(len(users), USERS)
                self.assertEqual(users[0].id, "user-0")
                self.assertEqual(users[-1].name, f"User {USERS - 1} Ünï 日本")
                self.assertEqual(users[-1].email, f"user-{USERS - 1}@example.com")
                self.assertEqual(users[1].status.value, "INACTIVE")
                self.assertEqual(users[USERS // 2].tags, ["alpha", "beta"])
                self.assertIsNone(users[0].address.zip)
                self.assertLess(elapsed, 30)

                await control.post(f"{FAULT_URL}/_arm", params={"fault": "huge-users"})
                self.assertEqual(len((await client.queries.fetch_big_users(count=USERS)).big_users), USERS)
            finally:
                await ws.close()
