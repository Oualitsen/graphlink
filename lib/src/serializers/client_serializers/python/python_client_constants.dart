import 'package:graphlink/src/persisted_queries.dart';

const pythonModelBase = r'''
from __future__ import annotations

from typing import Any, ClassVar, Dict, Optional

from pydantic import BaseModel, ConfigDict, model_serializer


class GraphLinkModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, protected_namespaces=())

    GL_TYPENAME: ClassVar[Optional[str]] = None

    @model_serializer(mode="wrap")
    def _gl_serialize(self, handler: Any) -> Any:
        data = handler(self)
        typename = type(self).GL_TYPENAME
        if typename is not None and isinstance(data, dict):
            return {"__typename": typename, **data}
        return data

    def to_json(self) -> Dict[str, Any]:
        return self.model_dump(mode="json", by_alias=True, serialize_as_any=True)

    @classmethod
    def from_json(cls, json: Dict[str, Any]) -> Any:
        return cls.model_validate(json)
''';

const pythonException = r'''
from __future__ import annotations

from typing import Any, Iterable, List


class GraphLinkException(Exception):
    errors: List[Any]

    def __init__(self, errors: Iterable[Any]) -> None:
        self.errors = list(errors)
        message = "; ".join(str(getattr(e, "message", e)) for e in self.errors)
        super().__init__(message or "GraphQL request failed")
''';

const pythonLock = r'''
from __future__ import annotations

import asyncio
from typing import Awaitable, Callable, TypeVar

T = TypeVar("T")


class GraphLinkLock:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()

    async def synchronized(self, fn: Callable[[], Awaitable[T]]) -> T:
        async with self._lock:
            return await fn()
''';

const pythonCacheEntry = r'''
from __future__ import annotations

import json
import time
from typing import Any, Dict


class GraphLinkCacheEntry:
    def __init__(self, data: str, expiry: int, stale: bool = False) -> None:
        self.data = data
        self.expiry = expiry
        self.stale = stale

    @staticmethod
    def from_json(value: Dict[str, Any]) -> "GraphLinkCacheEntry":
        return GraphLinkCacheEntry(value["data"], value["expiry"])

    def to_json(self) -> Dict[str, Any]:
        return {"data": self.data, "expiry": self.expiry}

    def encode(self) -> str:
        return json.dumps(self.to_json())

    @property
    def is_expired(self) -> bool:
        return int(time.time() * 1000) > self.expiry

    def as_stale(self) -> "GraphLinkCacheEntry":
        return GraphLinkCacheEntry(self.data, self.expiry, True)
''';

const pythonTagEntry = r'''
from __future__ import annotations

import json
from typing import Any, Dict, Iterable, Set


class GraphLinkTagEntry:
    def __init__(self, keys: Iterable[str] = ()) -> None:
        self.keys: Set[str] = set(keys)

    @staticmethod
    def from_json(value: Dict[str, Any]) -> "GraphLinkTagEntry":
        return GraphLinkTagEntry(value["keys"])

    def to_json(self) -> Dict[str, Any]:
        return {"keys": list(self.keys)}

    def encode(self) -> str:
        return json.dumps(self.to_json())

    @staticmethod
    def decode(raw: str) -> "GraphLinkTagEntry":
        return GraphLinkTagEntry.from_json(json.loads(raw))

    def add(self, key: str) -> None:
        self.keys.add(key)

    def remove(self, key: str) -> None:
        self.keys.discard(key)
''';

const pythonPartialQuery = r'''
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional


class GraphLinkPartialQuery:
    def __init__(
        self,
        *,
        query: str,
        variables: Dict[str, Any],
        ttl: int,
        tags: List[str],
        operation_name: str,
        element_key: str,
        fragment_names: List[str],
        argument_declarations: List[str],
        stale_if_offline: bool,
    ) -> None:
        self.query = query
        self.variables = variables
        self.ttl = ttl
        self.tags = tags
        self.operation_name = operation_name
        self.element_key = element_key
        self.fragment_names = fragment_names
        self.argument_declarations = argument_declarations
        self.stale_if_offline = stale_if_offline
        self.cache_key: Optional[str] = (
            None if ttl == 0 else self.compute_cache_key(operation_name, variables)
        )

    @staticmethod
    def compute_cache_key(operation_name: str, variables: Dict[str, Any]) -> str:
        sorted_variables = {k: variables[k] for k in sorted(variables)}
        raw = operation_name + ":" + json.dumps(sorted_variables, separators=(",", ":"))
        return GraphLinkPartialQuery._fnv1a(raw)

    @staticmethod
    def _fnv1a(value: str) -> str:
        result = 0x811C9DC5
        for char in value:
            result ^= ord(char)
            result = (result * 0x01000193) & 0xFFFFFFFF
        return format(result, "08x")
''';

const pythonCacheStore = r'''
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional


class GraphLinkCacheStore(ABC):
    @abstractmethod
    async def set(self, key: str, value: str) -> None: ...

    @abstractmethod
    async def get(self, key: str) -> Optional[str]: ...

    @abstractmethod
    async def invalidate(self, key: str) -> None: ...

    @abstractmethod
    async def invalidate_all(self) -> None: ...
''';

const pythonInMemoryCacheStore = r'''
from __future__ import annotations

from typing import Dict, Optional

from .graph_link_cache_store import GraphLinkCacheStore


class InMemoryGraphLinkCacheStore(GraphLinkCacheStore):
    def __init__(self) -> None:
        self._store: Dict[str, str] = {}

    async def set(self, key: str, value: str) -> None:
        self._store[key] = value

    async def get(self, key: str) -> Optional[str]:
        return self._store.get(key)

    async def invalidate(self, key: str) -> None:
        self._store.pop(key, None)

    async def invalidate_all(self) -> None:
        self._store.clear()
''';

const pythonUploads = r'''
from __future__ import annotations

import mimetypes
import os
from typing import Any, Awaitable, Callable, Dict, Optional

UploadProgressCallback = Callable[[int, int], None]


class GLUpload:
    def __init__(
        self,
        content: bytes,
        filename: Optional[str] = None,
        mime_type: str = "application/octet-stream",
    ) -> None:
        self.content = content
        self.filename = filename
        self.mime_type = mime_type

    @property
    def length(self) -> int:
        return len(self.content)

    @classmethod
    def from_bytes(
        cls,
        content: bytes,
        filename: Optional[str] = None,
        mime_type: str = "application/octet-stream",
    ) -> "GLUpload":
        return cls(content, filename, mime_type)

    @classmethod
    def from_file(cls, path: str, mime_type: Optional[str] = None) -> "GLUpload":
        with open(path, "rb") as handle:
            content = handle.read()
        guessed = mime_type or mimetypes.guess_type(path)[0] or "application/octet-stream"
        return cls(content, os.path.basename(path), guessed)


GLUploadConverter = Callable[[GLUpload], Any]
GLMultipartAdapter = Callable[[Dict[str, Any], Optional[UploadProgressCallback]], Awaitable[str]]
''';

const pythonUploadDefaultConverter = r'''
from __future__ import annotations

from typing import Any

from .graph_link_uploads import GLUpload


def default_upload_converter(upload: GLUpload) -> Any:
    return upload
''';

String pythonPersistedQueries({required bool useGet}) {
  final base = r'''
from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, Optional


def graph_link_sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class GraphLinkPersistedQueries:
    MIN_QUERY_LENGTH = __MIN_QUERY_LENGTH__
    NOT_FOUND = "PersistedQueryNotFound"
    NOT_SUPPORTED = "PersistedQueryNotSupported"

    @staticmethod
    def extensions(sha256_hash: str) -> Dict[str, Any]:
        return {"persistedQuery": {"version": 1, "sha256Hash": sha256_hash}}

    @staticmethod
    def failure(response: str) -> Optional[str]:
        if "PersistedQuery" not in response and "PERSISTED_QUERY" not in response:
            return None
        decoded = json.loads(response)
        errors = decoded.get("errors") if isinstance(decoded, dict) else None
        if not isinstance(errors, list):
            return None
        for error in errors:
            if not isinstance(error, dict):
                continue
            details = error.get("extensions")
            code = details.get("code") if isinstance(details, dict) else None
            message = error.get("message")
            if message == GraphLinkPersistedQueries.NOT_FOUND or code == "PERSISTED_QUERY_NOT_FOUND":
                return GraphLinkPersistedQueries.NOT_FOUND
            if message == GraphLinkPersistedQueries.NOT_SUPPORTED or code == "PERSISTED_QUERY_NOT_SUPPORTED":
                return GraphLinkPersistedQueries.NOT_SUPPORTED
        return None
'''
      .replaceAll('__MIN_QUERY_LENGTH__', '$persistedQueryMinLength');
  if (!useGet) return base;
  return '$base\n\n$_pythonGetRuntime';
}

const _pythonGetRuntime = r'''class GraphLinkGetNotSupported(Exception):
    def __init__(self, message: Optional[str] = None) -> None:
        self.message = message
        super().__init__(
            "GraphLinkGetNotSupported" if message is None else "GraphLinkGetNotSupported: " + message
        )


class GraphLinkGetRequest:
    @staticmethod
    def query_parameters(payload: str) -> Dict[str, str]:
        body = json.loads(payload)
        variables = body.get("variables")
        result: Dict[str, str] = {}
        if body.get("operationName") is not None:
            result["operationName"] = body["operationName"]
        if isinstance(variables, dict) and variables:
            result["variables"] = json.dumps(variables, separators=(",", ":"))
        result["extensions"] = json.dumps(body.get("extensions"), separators=(",", ":"))
        return result
''';

const pythonWsMessageTypes = r'''
from __future__ import annotations


class GraphqlWsMessageTypes:
    CONNECTION_INIT = "connection_init"
    CONNECTION_ACK = "connection_ack"
    SUBSCRIBE = "subscribe"
    PING = "ping"
    PONG = "pong"
    NEXT = "next"
    ERROR = "error"
    COMPLETE = "complete"
''';

const pythonWebSocketAdapter = r'''
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Callable, Dict, Optional


class GraphLinkWebSocketAdapter(ABC):
    def __init__(self) -> None:
        self.on_message: Callable[[str], None] = lambda message: None
        self.on_reconnect: Callable[[], None] = lambda: None

    @abstractmethod
    async def connect(self) -> None: ...

    @abstractmethod
    async def send_message(self, message: str) -> None: ...

    @abstractmethod
    async def close(self) -> None: ...

    async def connection_init_payload(self) -> Optional[Dict[str, Any]]:
        return None
''';

const pythonSubscriptionHandler = r'''
from __future__ import annotations

import asyncio
import json
import uuid
from typing import Any, AsyncIterator, Dict, Optional, Tuple

from .graph_link_exception import GraphLinkException
from .graph_link_websocket_adapter import GraphLinkWebSocketAdapter
from .graph_link_ws_message_types import GraphqlWsMessageTypes

_NEXT = "next"
_ERROR = "error"
_DONE = "done"


class GraphLinkSubscriptionHandler:
    def __init__(self, adapter: GraphLinkWebSocketAdapter) -> None:
        self.adapter = adapter
        self._queues: Dict[str, "asyncio.Queue[Tuple[str, Any]]"] = {}
        self._payloads: Dict[str, Any] = {}
        self._ack: Optional["asyncio.Future[None]"] = None
        self._acknowledged = False
        self._connect_lock = asyncio.Lock()
        adapter.on_message = self._on_message
        adapter.on_reconnect = self._on_reconnect

    async def _ensure_connected(self) -> None:
        async with self._connect_lock:
            if self._acknowledged:
                return
            await self.adapter.connect()
            await self._handshake()

    async def _handshake(self) -> None:
        self._acknowledged = False
        self._ack = asyncio.get_running_loop().create_future()
        payload = await self.adapter.connection_init_payload()
        init: Dict[str, Any] = {"type": GraphqlWsMessageTypes.CONNECTION_INIT}
        if payload is not None:
            init["payload"] = payload
        await self.adapter.send_message(json.dumps(init))
        await self._ack
        self._acknowledged = True

    def _subscribe_message(self, subscription_id: str, payload: Any) -> str:
        return json.dumps(
            {
                "id": subscription_id,
                "type": GraphqlWsMessageTypes.SUBSCRIBE,
                "payload": {
                    "query": payload.query,
                    "operationName": payload.operation_name,
                    "variables": payload.variables,
                },
            }
        )

    async def handle(self, payload: Any) -> AsyncIterator[Dict[str, Any]]:
        subscription_id = str(uuid.uuid4())
        queue: "asyncio.Queue[Tuple[str, Any]]" = asyncio.Queue()
        self._queues[subscription_id] = queue
        self._payloads[subscription_id] = payload
        try:
            await self._ensure_connected()
            await self.adapter.send_message(self._subscribe_message(subscription_id, payload))
            while True:
                kind, value = await queue.get()
                if kind == _NEXT:
                    yield value
                elif kind == _ERROR:
                    raise GraphLinkException(value)
                else:
                    return
        finally:
            self._queues.pop(subscription_id, None)
            self._payloads.pop(subscription_id, None)
            if self._acknowledged:
                try:
                    await self.adapter.send_message(
                        json.dumps({"id": subscription_id, "type": GraphqlWsMessageTypes.COMPLETE})
                    )
                except Exception:
                    pass

    def _on_message(self, raw: str) -> None:
        message = json.loads(raw)
        message_type = message.get("type")
        if message_type == GraphqlWsMessageTypes.CONNECTION_ACK:
            if self._ack is not None and not self._ack.done():
                self._ack.set_result(None)
            return
        if message_type == GraphqlWsMessageTypes.PING:
            asyncio.ensure_future(
                self.adapter.send_message(json.dumps({"type": GraphqlWsMessageTypes.PONG}))
            )
            return
        queue = self._queues.get(message.get("id"))
        if queue is None:
            return
        payload = message.get("payload")
        if message_type == GraphqlWsMessageTypes.NEXT and isinstance(payload, dict):
            queue.put_nowait((_NEXT, payload.get("data")))
        elif message_type == GraphqlWsMessageTypes.ERROR:
            queue.put_nowait((_ERROR, payload if isinstance(payload, list) else [payload]))
        elif message_type == GraphqlWsMessageTypes.COMPLETE:
            queue.put_nowait((_DONE, None))

    def _on_reconnect(self) -> None:
        asyncio.ensure_future(self._resubscribe())

    async def _resubscribe(self) -> None:
        if not self._payloads:
            return
        try:
            await self._handshake()
            for subscription_id, payload in list(self._payloads.items()):
                await self.adapter.send_message(self._subscribe_message(subscription_id, payload))
        except Exception as error:
            for queue in self._queues.values():
                queue.put_nowait((_ERROR, [error]))
''';

const pythonDefaultWebSocketAdapter = r'''
from __future__ import annotations

import asyncio
import random
from typing import Any, Awaitable, Callable, Dict, List, Optional

from websockets.asyncio.client import ClientConnection, connect

from .graph_link_websocket_adapter import GraphLinkWebSocketAdapter


class DefaultGraphLinkWebSocketAdapter(GraphLinkWebSocketAdapter):
    def __init__(
        self,
        *,
        url: str,
        headers_provider: Optional[Callable[[], Awaitable[Optional[Dict[str, str]]]]] = None,
        reconnect: bool = True,
        protocols: Optional[List[str]] = None,
        max_reconnect_attempts: Optional[int] = 10,
        max_reconnect_delay: float = 30.0,
    ) -> None:
        super().__init__()
        self.url = url
        self.headers_provider = headers_provider
        self.reconnect = reconnect
        self.protocols = protocols if protocols is not None else ["graphql-transport-ws"]
        self.max_reconnect_attempts = max_reconnect_attempts
        self.max_reconnect_delay = max_reconnect_delay
        self._connection: Optional[ClientConnection] = None
        self._reader: Optional["asyncio.Task[None]"] = None
        self._reconnecting = False
        self._disposed = False
        self._reconnect_attempts = 0

    @property
    def reconnect_attempts(self) -> int:
        return self._reconnect_attempts

    async def connect(self) -> None:
        if self._connection is not None:
            return
        try:
            self._connection = await connect(self.url, subprotocols=self.protocols)
        except Exception:
            if self.reconnect and not self._reconnecting and not self._disposed:
                asyncio.ensure_future(self._reconnect())
            raise
        self._reader = asyncio.ensure_future(self._read(self._connection))

    async def _read(self, connection: ClientConnection) -> None:
        try:
            async for message in connection:
                self.on_message(message if isinstance(message, str) else message.decode("utf-8"))
        except Exception:
            pass
        if self._connection is connection:
            self._connection = None
            if self.reconnect and not self._disposed and not self._reconnecting:
                asyncio.ensure_future(self._reconnect())

    def _backoff_delay(self, attempt: int) -> float:
        return min(1.0 * (2 ** attempt), self.max_reconnect_delay) + random.random()

    async def _reconnect(self) -> None:
        self._reconnecting = True
        try:
            cap = self.max_reconnect_attempts
            while not self._disposed and (cap is None or self._reconnect_attempts < cap):
                delay = self._backoff_delay(self._reconnect_attempts)
                self._reconnect_attempts += 1
                await asyncio.sleep(delay)
                if self._disposed:
                    break
                try:
                    self._connection = await connect(self.url, subprotocols=self.protocols)
                    self._reader = asyncio.ensure_future(self._read(self._connection))
                    self._reconnect_attempts = 0
                    self.on_reconnect()
                    return
                except Exception:
                    continue
        finally:
            self._reconnecting = False

    async def connection_init_payload(self) -> Optional[Dict[str, Any]]:
        if self.headers_provider is None:
            return None
        headers = await self.headers_provider()
        return dict(headers) if headers else None

    async def send_message(self, message: str) -> None:
        if self._connection is None:
            raise RuntimeError("WebSocket is not connected")
        await self._connection.send(message)

    async def close(self) -> None:
        self._disposed = True
        self._reconnect_attempts = 0
        connection, self._connection = self._connection, None
        if connection is not None:
            await connection.close(1000, "normal closure")
        if self._reader is not None:
            self._reader.cancel()
''';
