const ariadneRuntimeDir = 'runtime';

const ariadneSourceSupport = r'''
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

const ariadneLoaderRuntime = r'''
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

const ariadneGuards = r'''
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

const ariadneFileUpload = r'''
from __future__ import annotations

from dataclasses import dataclass
from inspect import isawaitable
from typing import Any, AsyncIterator, Callable, Optional

CHUNK = 64 * 1024


@dataclass
class FileUpload:
    filename: str
    mimetype: str
    encoding: str
    open_stream: Callable[[], AsyncIterator[bytes]]

    def create_read_stream(self) -> AsyncIterator[bytes]:
        return self.open_stream()


async def _settled(value: Any) -> Any:
    return await value if isawaitable(value) else value


def _stream_of(upload: Any) -> Callable[[], AsyncIterator[bytes]]:
    async def chunks() -> AsyncIterator[bytes]:
        await _settled(upload.seek(0))
        while True:
            chunk = await _settled(upload.read(CHUNK))
            if not chunk:
                return
            yield chunk

    return chunks


def to_file_upload(upload: Any) -> Optional[FileUpload]:
    """Wraps the file the multipart request parser produced (a Starlette `UploadFile` or a Django `UploadedFile`)."""
    if upload is None:
        return None
    return FileUpload(
        filename=getattr(upload, "filename", None) or getattr(upload, "name", None) or "",
        mimetype=upload.content_type or "application/octet-stream",
        encoding="7bit",
        open_stream=_stream_of(upload),
    )
''';

const ariadneContextBase = r'''
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

const ariadneWsHandler = r'''
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

const ariadneDjangoGraphQLView = r'''
from __future__ import annotations

import json
from typing import Any, Callable, Dict, List

from ariadne import graphql
from ariadne.file_uploads import combine_multipart_data
from asgiref.sync import sync_to_async
from django.core.exceptions import RequestDataTooBig
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.views.decorators.csrf import csrf_exempt

JSON = "application/json"
MULTIPART = "multipart/form-data"
TEXT = "text/plain; charset=utf-8"


class BadRequest(Exception):
    pass


def _plain(status: int, message: str = "") -> HttpResponse:
    return HttpResponse(message, status=status, content_type=TEXT)


def _not_allowed(request: HttpRequest) -> HttpResponse:
    allow = {"Allow": "OPTIONS, POST, GET"}
    if request.method == "OPTIONS":
        return HttpResponse(headers=allow)
    return HttpResponse(status=405, headers=allow)


def _from_json(request: HttpRequest) -> Any:
    try:
        return json.loads(request.body)
    except (TypeError, ValueError):
        raise BadRequest("Request body is not a valid JSON")


async def _from_multipart(request: HttpRequest) -> Any:
    try:
        fields, files = await sync_to_async(lambda: (request.POST, request.FILES))()
    except Exception:
        raise BadRequest("Request body is not a valid multipart/form-data")
    try:
        operations = json.loads(fields.get("operations"))
    except (TypeError, ValueError):
        raise BadRequest("Request 'operations' multipart field is not a valid JSON")
    try:
        files_map = json.loads(fields.get("map"))
    except (TypeError, ValueError):
        raise BadRequest("Request 'map' multipart field is not a valid JSON")
    return combine_multipart_data(operations, files_map, {key: value for key, value in files.items()})


def _from_query(request: HttpRequest) -> Dict[str, Any]:
    variables = request.GET.get("variables", "").strip()
    try:
        parsed = json.loads(variables) if variables else None
    except (TypeError, ValueError):
        raise BadRequest("Variables query arg is not a valid JSON")
    return {
        "query": request.GET["query"].strip(),
        "operationName": request.GET.get("operationName", "").strip() or None,
        "variables": parsed,
    }


async def _read(request: HttpRequest) -> Any:
    kind = request.headers.get("content-type", "").split(";")[0]
    try:
        if kind == JSON:
            return _from_json(request)
        if kind == MULTIPART:
            return await _from_multipart(request)
    except RequestDataTooBig:
        raise BadRequest("Request body is too large")
    if request.method == "GET" and request.GET.get("query"):
        return _from_query(request)
    raise BadRequest(f"Posted content must be of type {JSON} or {MULTIPART}")


def build_graphql_view(
    schema: Any,
    create_context: Callable[[Any], Any],
    validation_rules: List[Any],
    error_formatter: Callable[..., Any],
) -> Callable[[HttpRequest], Any]:
    async def view(request: HttpRequest) -> HttpResponse:
        if request.method == "GET":
            if not request.GET.get("query"):
                return _not_allowed(request)
        elif request.method != "POST":
            return _not_allowed(request)
        try:
            data = await _read(request)
        except BadRequest as error:
            return _plain(400, str(error))
        success, result = await graphql(
            schema,
            data,
            context_value=create_context(request),
            validation_rules=validation_rules,
            require_query=request.method == "GET",
            debug=False,
            error_formatter=error_formatter,
        )
        return JsonResponse(result, status=200 if success else 400)

    return csrf_exempt(view)
''';

const ariadneDjangoWebSocket = r'''
from typing import Any, Awaitable, Callable, Dict

Scope = Dict[str, Any]
Receive = Callable[[], Awaitable[Dict[str, Any]]]
Send = Callable[[Dict[str, Any]], Awaitable[None]]


class GraphLinkWebSocketRouter:
    """Django serves HTTP only: this wrapper hands the GraphQL WebSocket path to Ariadne and answers `lifespan` itself."""

    def __init__(self, django_app: Any, graphql_path: str, graphql_app: Any) -> None:
        self.django_app = django_app
        self.graphql_path = graphql_path
        self.graphql_app = graphql_app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        kind = scope["type"]
        if kind == "lifespan":
            await self._lifespan(receive, send)
        elif kind == "websocket":
            if scope.get("path") == self.graphql_path:
                await self.graphql_app(scope, receive, send)
            else:
                await receive()
                await send({"type": "websocket.close", "code": 1000})
        else:
            await self.django_app(scope, receive, send)

    async def _lifespan(self, receive: Receive, send: Send) -> None:
        while True:
            message = await receive()
            if message["type"] == "lifespan.startup":
                await send({"type": "lifespan.startup.complete"})
            elif message["type"] == "lifespan.shutdown":
                await send({"type": "lifespan.shutdown.complete"})
                return
''';
