import asyncio
import os
from typing import Any, AsyncIterator

from generated import GraphLinkClient

TIMEOUT = 10


def port() -> int:
    return int(os.environ.get("SERVER_PORT", "9997"))


def new_client() -> GraphLinkClient:
    return GraphLinkClient.with_http(
        url=f"http://localhost:{port()}/graphql",
        ws_url=f"ws://localhost:{port()}/graphql",
    )


async def first(stream: AsyncIterator[Any]) -> Any:
    try:
        return await asyncio.wait_for(stream.__anext__(), TIMEOUT)
    finally:
        await stream.aclose()


async def start_first(stream: AsyncIterator[Any]) -> "asyncio.Task[Any]":
    task = asyncio.ensure_future(first(stream))
    await asyncio.sleep(0.3)
    return task
