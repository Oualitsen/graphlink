import asyncio
import subprocess
import unittest
from typing import Optional

from .real_server import DEFAULT_PORT, new_client, new_ws_adapter, server_jar


def listening_pids(port: int) -> list:
    result = subprocess.run(["lsof", "-ti", f":{port}", "-sTCP:LISTEN"], capture_output=True, text=True)
    return [pid for pid in result.stdout.split() if pid]


@unittest.skipIf(server_jar() is None, "SERVER_JAR env var not set - run via make reconnect-test")
class SubscriptionReconnectTest(unittest.IsolatedAsyncioTestCase):
    async def test_counter_tick_resumes_after_server_restart(self) -> None:
        ws = new_ws_adapter()
        client = new_client(ws_adapter=ws)
        reconnected = asyncio.Event()
        original = ws.on_reconnect

        def on_reconnect() -> None:
            original()
            reconnected.set()

        ws.on_reconnect = on_reconnect

        ticks = 0
        first_tick = asyncio.Event()
        after_reconnect = asyncio.Event()

        async def consume() -> None:
            nonlocal ticks
            try:
                async for _ in client.subscriptions.counter_tick():
                    ticks += 1
                    if not first_tick.is_set():
                        first_tick.set()
                    elif reconnected.is_set():
                        after_reconnect.set()
            except Exception:
                pass

        consumer = asyncio.ensure_future(consume())
        new_process: Optional[subprocess.Popen] = None
        try:
            await asyncio.wait_for(first_tick.wait(), 10)
            for pid in listening_pids(DEFAULT_PORT):
                subprocess.run(["kill", "-9", pid])
            await asyncio.sleep(0.5)
            new_process = subprocess.Popen(["java", "-jar", server_jar()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            await asyncio.wait_for(reconnected.wait(), 30)
            await asyncio.wait_for(after_reconnect.wait(), 15)
        finally:
            consumer.cancel()
            await ws.close()
            if new_process is not None:
                new_process.kill()


if __name__ == "__main__":
    unittest.main()
