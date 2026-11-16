const fastapiRuntimeDir = 'runtime';

const fastapiSourceSupport = r'''
from __future__ import annotations

from typing import Any, Dict, Optional

SOURCE_KEY = "__glSource__"


def attach_source(value: Any) -> Optional[Dict[str, Any]]:
    if value is None:
        return None
    return {**value.to_json(), SOURCE_KEY: value}


def source_of(json: Any) -> Any:
    if isinstance(json, dict):
        return json.get(SOURCE_KEY, json)
    return json
''';

const fastapiLoaderRuntime = r'''
from __future__ import annotations

import asyncio
from typing import Any, Awaitable, Callable, Dict, Generic, List, Tuple, TypeVar

K = TypeVar("K")
V = TypeVar("V")


class GraphLinkLoader(Generic[K, V]):
    """Collects the keys requested in one event-loop tick and resolves them with a single batch call."""

    def __init__(self, batch_load: Callable[[List[K]], Awaitable[List[Any]]]) -> None:
        self._batch_load = batch_load
        self._cache: Dict[int, Tuple[K, "asyncio.Future[V]"]] = {}
        self._queue: List[Tuple[K, "asyncio.Future[V]"]] = []
        self._scheduled = False

    def load(self, key: K) -> "asyncio.Future[V]":
        cached = self._cache.get(id(key))
        if cached is not None:
            return cached[1]
        loop = asyncio.get_running_loop()
        future: "asyncio.Future[V]" = loop.create_future()
        self._cache[id(key)] = (key, future)
        self._queue.append((key, future))
        if not self._scheduled:
            self._scheduled = True
            loop.call_soon(lambda: asyncio.ensure_future(self._dispatch()))
        return future

    async def _dispatch(self) -> None:
        queue, self._queue, self._scheduled = self._queue, [], False
        try:
            values = await self._batch_load([key for key, _ in queue])
        except Exception as error:
            for _, future in queue:
                if not future.done():
                    future.set_exception(error)
            return
        for (_, future), value in zip(queue, values):
            if future.done():
                continue
            if isinstance(value, Exception):
                future.set_exception(value)
            else:
                future.set_result(value)
''';

const fastapiGuards = r'''
from __future__ import annotations

from typing import Any, Dict, List, Optional, Set, Tuple, Type

from graphql import (
    DocumentNode,
    FieldNode,
    FragmentDefinitionNode,
    FragmentSpreadNode,
    GraphQLError,
    InlineFragmentNode,
    OperationDefinitionNode,
    SelectionSetNode,
)
from graphql.validation import ASTValidationRule

DEFAULT_MAX_QUERY_DEPTH = 32


def query_depth(document: DocumentNode, limit: int) -> int:
    fragments: Dict[str, SelectionSetNode] = {}
    for definition in document.definitions:
        if isinstance(definition, FragmentDefinitionNode):
            fragments[definition.name.value] = definition.selection_set
    pending: List[Tuple[SelectionSetNode, int, frozenset]] = []
    for definition in document.definitions:
        if isinstance(definition, OperationDefinitionNode):
            pending.append((definition.selection_set, 1, frozenset()))
    deepest = 0
    while pending and deepest <= limit:
        selection_set, depth, visited = pending.pop()
        deepest = max(deepest, depth)
        for selection in selection_set.selections:
            if isinstance(selection, FieldNode):
                if selection.selection_set is not None:
                    pending.append((selection.selection_set, depth + 1, visited))
            elif isinstance(selection, InlineFragmentNode):
                pending.append((selection.selection_set, depth, visited))
            elif isinstance(selection, FragmentSpreadNode):
                name = selection.name.value
                fragment = fragments.get(name)
                if name not in visited and fragment is not None:
                    pending.append((fragment, depth, visited | {name}))
    return deepest


def max_depth_rule(limit: int) -> Type[ASTValidationRule]:
    class MaxDepthRule(ASTValidationRule):
        def enter_document(self, node: DocumentNode, *_args: Any) -> None:
            if query_depth(node, limit) > limit:
                self.report_error(
                    GraphQLError(
                        f"Query is too deep: the maximum depth is {limit}.",
                        extensions={"code": "GRAPHQL_VALIDATION_FAILED"},
                    )
                )

    return MaxDepthRule


def format_error(error: GraphQLError, debug: bool = False) -> Dict[str, Any]:
    formatted: Dict[str, Any] = {"message": error.message}
    if error.locations:
        formatted["locations"] = [{"line": l.line, "column": l.column} for l in error.locations]
    if error.path:
        formatted["path"] = list(error.path)
    extensions = dict(error.extensions or {})
    if "code" not in extensions:
        extensions["code"] = "INTERNAL_SERVER_ERROR" if error.original_error is not None else "GRAPHQL_VALIDATION_FAILED"
    formatted["extensions"] = extensions
    return formatted
''';

const fastapiFileUpload = r'''
from __future__ import annotations

from dataclasses import dataclass
from typing import AsyncIterator, Callable


@dataclass
class FileUpload:
    filename: str
    mimetype: str
    encoding: str
    open_stream: Callable[[], AsyncIterator[bytes]]

    def create_read_stream(self) -> AsyncIterator[bytes]:
        return self.open_stream()
''';

const fastapiContextBase = r'''
from __future__ import annotations

from typing import Any, Optional


class GraphLinkLoaders:
    """Per-request batch loaders, one attribute per `@glSkipOnServer(batch: true)` mapping."""


class GraphLinkContext:
    """The request context. Add attributes freely (`context.user = ...`); `request` is the Starlette request or websocket."""

    request: Any
    loaders: Any

    def __init__(self, request: Optional[Any] = None) -> None:
        self.request = request
        self.loaders = GraphLinkLoaders()
''';

const fastapiWsHandler = r'''
from __future__ import annotations

import json
from typing import Any

from ariadne.asgi.handlers import GraphQLTransportWSHandler
from starlette.types import Receive, Scope, Send
from starlette.websockets import WebSocket, WebSocketDisconnect


class GraphLinkWebSocket(WebSocket):
    async def receive_json(self, mode: str = "text") -> Any:
        text = await self.receive_text()
        try:
            return json.loads(text)
        except ValueError:
            await self.close(code=4400)
            raise WebSocketDisconnect(4400)


class GraphLinkWSHandler(GraphQLTransportWSHandler):
    """graphql-transport-ws handler that answers a malformed frame with the protocol's 4400 close code."""

    async def handle(self, scope: Scope, receive: Receive, send: Send) -> None:
        await self.handle_websocket(GraphLinkWebSocket(scope=scope, receive=receive, send=send))

    async def handle_websocket_message(self, websocket: WebSocket, message: Any, client_context: Any) -> None:
        if not isinstance(message, dict):
            await websocket.close(code=4400)
            return
        await super().handle_websocket_message(websocket, message, client_context)

    async def handle_websocket_subscribe(
        self, websocket: WebSocket, data: Any, operation_id: str, client_context: Any
    ) -> None:
        if not isinstance(data, dict) or not isinstance(operation_id, str):
            await websocket.close(code=4400)
            return
        await super().handle_websocket_subscribe(websocket, data, operation_id, client_context)
''';
