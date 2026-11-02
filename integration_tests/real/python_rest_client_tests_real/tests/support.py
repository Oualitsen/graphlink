import hashlib
import unittest
from typing import Any, Awaitable, Callable, Dict, List, Optional

import httpx

from generated import (
    Echo,
    GLUpload,
    GraphLinkClient,
    GraphLinkHttpxAdapter,
    GraphLinkRestHttpxAdapter,
    InMemoryGraphLinkCacheStore,
    Part,
)

from .variant import PORT

SERVER_URL = f"http://127.0.0.1:{PORT}"


class RestTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self._closers: List[Callable[[], Awaitable[None]]] = []
        async with httpx.AsyncClient() as http:
            await http.post(f"{SERVER_URL}/_reset")
        self.client = self.new_client()

    async def asyncTearDown(self) -> None:
        for close in self._closers:
            await close()

    def new_client(
        self,
        base_url: Optional[str] = None,
        headers: Optional[Callable[[], Any]] = None,
        store: Optional[InMemoryGraphLinkCacheStore] = None,
    ) -> GraphLinkClient:
        base = base_url if base_url is not None else SERVER_URL
        rest = GraphLinkRestHttpxAdapter(base_url=base, headers_provider=headers)
        graphql = GraphLinkHttpxAdapter(url=f"{base}/graphql")
        self._closers.append(rest.aclose)
        self._closers.append(graphql.aclose)
        return GraphLinkClient(adapter=graphql.call, rest_adapter=rest, store=store)


def pair(p: Any) -> str:
    return f"{p.name}={p.value}"


def query_pairs(e: Echo) -> List[str]:
    return [pair(p) for p in e.query]


def form_pairs(e: Echo) -> List[str]:
    return [pair(p) for p in e.form]


def header(e: Echo, name: str) -> Optional[str]:
    for h in e.headers:
        if h.name == name.lower():
            return h.value
    return None


def part(e: Echo, name: str) -> Part:
    for p in e.parts:
        if p.name == name:
            return p
    raise AssertionError(f"no part named {name}")


def parts_named(e: Echo, name: str) -> List[Part]:
    return [p for p in e.parts if p.name == name]


def query_value(e: Echo, name: str) -> Optional[str]:
    for p in e.query:
        if p.name == name:
            return p.value
    return None


def form_value(e: Echo, name: str) -> Optional[str]:
    for p in e.form:
        if p.name == name:
            return p.value
    return None


def pattern(size: int) -> bytes:
    return bytes(i % 251 for i in range(size))


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def upload_of(data: bytes, filename: Optional[str] = None, mime_type: str = "application/octet-stream") -> GLUpload:
    return GLUpload(data, filename, mime_type)
