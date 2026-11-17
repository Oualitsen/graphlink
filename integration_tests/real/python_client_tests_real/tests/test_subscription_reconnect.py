import asyncio
import os
import socket
import subprocess
import time
import unittest
from typing import Optional

from .real_server import new_client, new_ws_adapter

SERVER_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "fault_server", "server.py")


def listening_pids(port: int) -> list:
    result = subprocess.run(["lsof", "-ti", f":{port}", "-sTCP:LISTEN"], capture_output=True, text=True)
    return [pid for pid in result.stdout.split() if pid]


def kill_port(port: int) -> None:
    for pid in listening_pids(port):
        subprocess.run(["kill", "-9", pid])


def start_server(port: int) -> subprocess.Popen:
    kill_port(port)
    process = subprocess.Popen(
        ["python3", SERVER_SCRIPT, "--port", str(port), "--live"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 30
    while time.time() < deadline:
        with socket.socket() as probe:
            if probe.connect_ex(("localhost", port)) == 0:
                return process
        time.sleep(0.5)
    process.kill()
    raise RuntimeError(f"server on port {port} did not start within 30 s")


class SubscriptionReconnectTest(unittest.IsolatedAsyncioTestCase):
    async def test_counter_tick_resumes_after_server_restart(self) -> None:
        port = 9993
        await asyncio.to_thread(start_server, port)
        ws = new_ws_adapter(port)
        client = new_client(port, ws_adapter=ws)
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
        try:
            await asyncio.wait_for(first_tick.wait(), 10)
            kill_port(port)
            await asyncio.sleep(0.5)
            start_server(port)
            await asyncio.wait_for(reconnected.wait(), 30)
            await asyncio.wait_for(after_reconnect.wait(), 15)
        finally:
            consumer.cancel()
            await ws.close()
            kill_port(port)

    async def test_the_rotated_token_is_sent_when_the_subscription_resumes(self) -> None:
        port = 9996
        first, second = f"py-first-{time.time_ns()}", f"py-second-{time.time_ns()}"
        current = {"token": first}

        async def provider() -> dict:
            return {"Authorization": f"Bearer {current['token']}"}

        process = start_server(port)
        ws = new_ws_adapter(port, headers_provider=provider)
        client = new_client(port, ws_adapter=ws)
        first_tick = asyncio.Event()

        async def consume() -> None:
            try:
                async for _ in client.subscriptions.secure_ticks(count=1000):
                    first_tick.set()
            except Exception:
                pass

        consumer = asyncio.ensure_future(consume())
        restarted: Optional[subprocess.Popen] = None
        try:
            await asyncio.wait_for(first_tick.wait(), 10)
            self.assertEqual((await client.queries.secure_tick_starts(token=first)).secure_tick_starts, 1)

            current["token"] = second
            kill_port(port)
            await asyncio.sleep(0.5)
            restarted = start_server(port)

            deadline = time.time() + 60
            while True:
                try:
                    if (await client.queries.secure_tick_starts(token=second)).secure_tick_starts == 1:
                        break
                except Exception:
                    pass
                self.assertLess(time.time(), deadline, "the subscription was not resumed with the rotated token")
                await asyncio.sleep(1)
            self.assertEqual((await client.queries.secure_tick_starts(token=first)).secure_tick_starts, 0)
        finally:
            consumer.cancel()
            await ws.close()
            for running in (process, restarted):
                if running is not None:
                    running.kill()
            kill_port(port)


if __name__ == "__main__":
    unittest.main()
