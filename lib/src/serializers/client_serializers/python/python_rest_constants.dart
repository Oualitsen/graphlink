const pythonRestFile = r'''
from __future__ import annotations

import json
import random
import re
import time
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Awaitable, Callable, Dict, List, Optional, Tuple, Union
from urllib.parse import quote, quote_plus, unquote

from .graph_link_uploads import GLUpload, UploadProgressCallback

DownloadProgressCallback = Callable[[int, int], None]


@dataclass
class RestPart:
    name: str
    value: Optional[str] = None
    file: Optional[GLUpload] = None
    mime_type: Optional[str] = None


@dataclass
class RestJsonBody:
    json: str


@dataclass
class RestFormBody:
    fields: List[Tuple[str, str]]


@dataclass
class RestMultipartBody:
    parts: List[RestPart]


@dataclass
class RestRawBody:
    upload: GLUpload


RestBody = Union[RestJsonBody, RestFormBody, RestMultipartBody, RestRawBody]


@dataclass
class RestRequest:
    method: str
    path: str
    query: List[Tuple[str, str]] = field(default_factory=list)
    headers: Dict[str, str] = field(default_factory=dict)
    body: Optional[RestBody] = None
    on_send_progress: Optional[UploadProgressCallback] = None


async def rest_read_all(source: AsyncIterator[bytes]) -> bytes:
    chunks: List[bytes] = []
    async for chunk in source:
        chunks.append(chunk)
    return b"".join(chunks)


async def _single_chunk(data: bytes) -> AsyncIterator[bytes]:
    if data:
        yield data


class RestResponse:
    def __init__(self, status: int, stream: AsyncIterator[bytes], headers: Optional[Dict[str, str]] = None) -> None:
        self.status = status
        self.stream = stream
        self.headers: Dict[str, str] = headers if headers is not None else {}

    @staticmethod
    def from_bytes(status: int, data: bytes, headers: Optional[Dict[str, str]] = None) -> "RestResponse":
        return RestResponse(status, _single_chunk(data), headers)

    @staticmethod
    def from_text(status: int, text: str, headers: Optional[Dict[str, str]] = None) -> "RestResponse":
        return RestResponse.from_bytes(status, text.encode("utf-8"), headers)

    @property
    def is_success(self) -> bool:
        return 200 <= self.status < 300

    async def bytes(self) -> bytes:
        return await rest_read_all(self.stream)

    async def text(self) -> str:
        return (await self.bytes()).decode("utf-8")

    async def json(self) -> Any:
        body = await self.text()
        return None if len(body) == 0 else json.loads(body)

    async def drain(self) -> None:
        await self.bytes()


class RestError(Exception):
    def __init__(self, status: int, headers: Dict[str, str], body: str) -> None:
        super().__init__(f"RestError({status}): {body}")
        self.status = status
        self.headers = headers
        self.body = body

    @staticmethod
    async def from_response(response: RestResponse) -> "RestError":
        return RestError(response.status, response.headers, await response.text())


def _header(headers: Dict[str, str], name: str) -> Optional[str]:
    for key, value in headers.items():
        if key.lower() == name:
            return value
    return None


class GLDownload:
    def __init__(
        self,
        stream: AsyncIterator[bytes],
        filename: Optional[str] = None,
        content_type: Optional[str] = None,
        length: Optional[int] = None,
    ) -> None:
        self.stream = stream
        self.filename = filename
        self.content_type = content_type
        self.length = length

    @staticmethod
    def from_response(response: RestResponse, on_progress: Optional[DownloadProgressCallback] = None) -> "GLDownload":
        raw_length = _header(response.headers, "content-length")
        length = int(raw_length) if raw_length is not None and raw_length.isdigit() else None
        source = response.stream
        if on_progress is not None:
            source = GLDownload._counted(source, length, on_progress)
        disposition = _header(response.headers, "content-disposition")
        match = None if disposition is None else re.search(r"filename\*?=(?:UTF-8'')?\"?([^\";]+)\"?", disposition, re.I)
        filename = None if match is None else _decode_filename(match.group(1))
        return GLDownload(source, filename, _header(response.headers, "content-type"), length)

    @staticmethod
    async def _counted(
        source: AsyncIterator[bytes], total: Optional[int], on_progress: DownloadProgressCallback
    ) -> AsyncIterator[bytes]:
        received = 0
        async for chunk in source:
            received += len(chunk)
            on_progress(received, -1 if total is None else total)
            yield chunk

    async def bytes(self) -> bytes:
        return await rest_read_all(self.stream)


def _decode_filename(value: str) -> str:
    try:
        return unquote(value, errors="strict")
    except UnicodeDecodeError:
        return value


async def gl_no_graphql__(*_args: Any) -> str:
    raise RuntimeError("This schema has no GraphQL operation: pass no GraphQL adapter")


GLRestAdapter = Callable[[RestRequest], Awaitable[RestResponse]]


def rest_encode(value: str) -> str:
    return quote(value, safe="")


def rest_encode_query(value: str) -> str:
    return quote_plus(value, safe="")


def rest_encode_json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def rest_url(base_url: str, request: RestRequest) -> str:
    base = base_url[:-1] if base_url.endswith("/") else base_url
    query = "&".join(f"{rest_encode_query(k)}={rest_encode_query(v)}" for k, v in request.query)
    return f"{base}{request.path}{'?' + query if query else ''}"


def rest_form_body(fields: List[Tuple[str, str]]) -> str:
    return "&".join(f"{rest_encode_query(k)}={rest_encode_query(v)}" for k, v in fields)


def rest_multipart_stream(
    parts: List[RestPart], on_progress: Optional[UploadProgressCallback] = None
) -> Tuple[str, Optional[int], AsyncIterator[bytes]]:
    boundary = f"----graphlink{random.getrandbits(48):x}{int(time.time() * 1000):x}"

    def quoted(text: str) -> str:
        return text.replace('"', "%22").replace("\r", "%0D").replace("\n", "%0A")

    heads: List[bytes] = []
    lengths: List[Optional[int]] = []
    for part in parts:
        upload = part.file
        disposition = f'form-data; name="{quoted(part.name)}"'
        if upload is not None and upload.filename is not None:
            disposition += f'; filename="{quoted(upload.filename)}"'
        mime_type = part.mime_type if upload is None else upload.mime_type
        head = f"--{boundary}\r\nContent-Disposition: {disposition}\r\n"
        if mime_type is not None:
            head += f"Content-Type: {mime_type}\r\n"
        heads.append(f"{head}\r\n".encode("utf-8"))
        lengths.append(len((part.value or "").encode("utf-8")) if upload is None else upload.length)
    tail = f"--{boundary}--\r\n".encode("utf-8")
    known = all(length is not None for length in lengths)
    total = sum(len(h) + (n or 0) + 2 for h, n in zip(heads, lengths)) + len(tail) if known else None

    async def body() -> AsyncIterator[bytes]:
        for part, head in zip(parts, heads):
            yield head
            if part.file is None:
                yield (part.value or "").encode("utf-8")
            else:
                async for chunk in part.file.chunks():
                    yield chunk
            yield b"\r\n"
        yield tail

    return f"multipart/form-data; boundary={boundary}", total, rest_counted_stream(body(), total, on_progress)


async def rest_counted_stream(
    source: AsyncIterator[bytes], total: Optional[int], on_progress: Optional[UploadProgressCallback]
) -> AsyncIterator[bytes]:
    sent = 0
    async for chunk in source:
        sent += len(chunk)
        yield chunk
        if on_progress is not None:
            on_progress(sent, -1 if total is None else total)


def rest_text(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return value if isinstance(value, str) else str(value)


def _rest_collect(
    out: List[Tuple[str, str]], key: str, value: Any, bracket: bool, comma: bool, in_list: bool
) -> None:
    if value is None:
        return
    if isinstance(value, list):
        items = [e for e in value if e is not None]
        if not items:
            return
        if not in_list and all(not isinstance(e, (dict, list)) for e in items):
            if comma:
                out.append((key, ",".join(rest_text(e) for e in items)))
            else:
                out.extend((key, rest_text(e)) for e in items)
        else:
            for index, element in enumerate(value):
                nested = f"{key}[{index}]" if bracket else f"{key}.{index}"
                _rest_collect(out, nested, element, bracket, comma, True)
    elif isinstance(value, dict):
        for name, element in value.items():
            nested = f"{key}[{name}]" if bracket else f"{key}.{name}"
            _rest_collect(out, nested, element, bracket, comma, False)
    else:
        out.append((key, rest_text(value)))


def rest_entries(key: str, value: Any, bracket: bool = False, comma: bool = False) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    _rest_collect(out, key, value, bracket, comma, False)
    return out


def rest_spread_entries(
    json_value: Any, names: Dict[str, str], bracket: bool = False, comma: bool = False
) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    if isinstance(json_value, dict):
        for name, wire in names.items():
            _rest_collect(out, wire, json_value.get(name), bracket, comma, False)
    return out


def rest_header_value(value: Any) -> str:
    if isinstance(value, list):
        return ",".join(rest_text(e) for e in value if e is not None)
    return rest_text(value)


def rest_header(name: str, value: Any) -> Dict[str, str]:
    return {} if value is None else {name: rest_header_value(value)}


def rest_headers(json_value: Any, names: Dict[str, str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if isinstance(json_value, dict):
        for name, header in names.items():
            value = json_value.get(name)
            if value is not None:
                out[header] = rest_header_value(value)
    return out


def rest_parts(entries: List[Tuple[str, str]]) -> List[RestPart]:
    return [RestPart(name=name, value=value) for name, value in entries]


def rest_navigate(json_value: Any, path: List[str]) -> Any:
    current = json_value
    for segment in path:
        current = current.get(segment) if isinstance(current, dict) else None
    return current
''';

const pythonRestResolver = r'''
class GraphLinkRestResolver(GraphLinkResolverBase):
    rest_adapter: GLRestAdapter

    async def rest_call__(self, request: RestRequest) -> RestResponse:
        response = await self.rest_adapter(request)
        if not response.is_success:
            raise await RestError.from_response(response)
        return response

    async def rest_void__(self, request: RestRequest) -> None:
        response = await self.rest_call__(request)
        await response.drain()

    async def rest_download__(
        self,
        request: RestRequest,
        allow_empty: bool,
        on_progress: Optional[DownloadProgressCallback] = None,
    ) -> Optional[GLDownload]:
        response = await self.rest_call__(request)
        if response.status == 204:
            await response.drain()
            if allow_empty:
                return None
            raise ValueError(f"Empty REST response for a non-null download of {request.method} {request.path}")
        return GLDownload.from_response(response, on_progress)

    async def rest_text__(self, request: RestRequest) -> str:
        return await (await self.rest_call__(request)).text()

    async def rest_text_or_null__(self, request: RestRequest) -> Optional[str]:
        text = await (await self.rest_call__(request)).text()
        return None if len(text) == 0 else text

    async def rest_json__(self, request: RestRequest, path: List[str], allow_empty: bool) -> Any:
        value = rest_navigate(await (await self.rest_call__(request)).json(), path)
        if value is None and not allow_empty:
            raise ValueError(f"Empty REST response for a non-null result of {request.method} {request.path}")
        return value

    async def rest_cached__(
        self,
        name: str,
        variables: Dict[str, Any],
        ttl: int,
        tags: List[str],
        stale_if_offline: bool,
        fetch: Callable[[], Awaitable[Any]],
        decode: Callable[[Any], T],
    ) -> T:
        key = GraphLinkPartialQuery.compute_cache_key(name, variables)
        cached = await self.get_from_cache(key, tags, stale_if_offline)
        if cached is not None and not cached.stale:
            return decode(json.loads(cached.data))
        try:
            payload = await fetch()
        except RestError:
            raise
        except Exception:
            if cached is not None:
                return decode(json.loads(cached.data))
            raise
        value = decode(payload)
        if payload is not None:
            entry = GraphLinkCacheEntry(json.dumps(payload), int(time.time() * 1000) + ttl * 1000)
            await self.gl_store__.set(key, json.dumps(entry.to_json()))
            if tags:
                await self.add_key_to_tags(key, tags)
        return value
''';

const pythonRestHttpxAdapter = r'''
class GraphLinkRestHttpxAdapter:
    def __init__(
        self,
        *,
        base_url: str,
        headers_provider: Optional[Callable[[], Any]] = None,
        client: Optional[httpx.AsyncClient] = None,
    ) -> None:
        self.base_url = base_url
        self.headers_provider = headers_provider
        self.client = client if client is not None else httpx.AsyncClient(follow_redirects=True)

    async def _extra_headers(self) -> Dict[str, str]:
        if self.headers_provider is None:
            return {}
        provided = self.headers_provider()
        if inspect.isawaitable(provided):
            provided = await provided
        return dict(provided) if provided else {}

    async def __call__(self, request: RestRequest) -> RestResponse:
        headers = {**await self._extra_headers(), **request.headers}
        content: Any = None
        body = request.body
        if isinstance(body, RestJsonBody):
            content = body.json.encode("utf-8")
        elif isinstance(body, RestFormBody):
            content = rest_form_body(body.fields).encode("utf-8")
        elif isinstance(body, RestMultipartBody):
            headers["Content-Type"], length, content = rest_multipart_stream(body.parts, request.on_send_progress)
            if length is not None:
                headers["Content-Length"] = str(length)
        elif isinstance(body, RestRawBody):
            upload = body.upload
            if upload.length is not None:
                headers["Content-Length"] = str(upload.length)
            content = rest_counted_stream(upload.chunks(), upload.length, request.on_send_progress)
        built = self.client.build_request(request.method, rest_url(self.base_url, request), headers=headers, content=content)
        response = await self.client.send(built, stream=True)

        async def stream() -> AsyncIterator[bytes]:
            try:
                async for chunk in response.aiter_bytes():
                    yield chunk
            finally:
                await response.aclose()

        return RestResponse(response.status_code, stream(), dict(response.headers))

    async def aclose(self) -> None:
        await self.client.aclose()
''';
