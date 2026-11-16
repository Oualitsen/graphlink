const fastapiRestSupport = r'''
import json
import math
import re
import sys
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict, List, Optional
from urllib.parse import parse_qsl

from starlette.requests import Request
from starlette.responses import JSONResponse, Response

INT_MIN = -2147483648
INT_MAX = 2147483647
MAX_JSON_BODY = 100 * 1024

REASONS = {
    400: "Bad Request",
    404: "Not Found",
    405: "Method Not Allowed",
    413: "Payload Too Large",
    415: "Unsupported Media Type",
    500: "Internal Server Error",
}

Shape = Dict[str, Any]
Shapes = Dict[str, Shape]
Options = Dict[str, Any]
Params = Dict[str, List[str]]

S: Dict[str, Shape] = {
    "string": {"k": "string"},
    "int": {"k": "int"},
    "float": {"k": "float"},
    "boolean": {"k": "boolean"},
}


class RestError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def bad(message: str) -> Any:
    raise RestError(400, message)


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and INT_MIN <= value <= INT_MAX


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def parse_scalar(text: str, shape: Shape) -> Any:
    kind = shape["k"]
    if kind == "int":
        if not re.fullmatch(r"-?\d+", text) or not _is_int(int(text)):
            bad("Invalid integer")
        return int(text)
    if kind == "float":
        if not re.fullmatch(r"-?\d+(\.\d+)?([eE][+-]?\d+)?", text) or not math.isfinite(float(text)):
            bad("Invalid number")
        return float(text)
    if kind == "boolean":
        if text != "true" and text != "false":
            bad("Invalid boolean")
        return text == "true"
    if kind == "enum":
        if text not in shape["values"]:
            bad("Invalid enum value")
        return text
    return text


def validate(value: Any, shape: Shape, shapes: Shapes) -> None:
    kind = shape["k"]
    if kind == "ref":
        return validate(value, shapes[shape["name"]], shapes)
    if kind == "string":
        if not isinstance(value, str):
            bad("Expected a string")
    elif kind == "int":
        if not _is_int(value) and not (isinstance(value, float) and value.is_integer() and _is_int(int(value))):
            bad("Expected an integer")
    elif kind == "float":
        if not _is_number(value):
            bad("Expected a number")
    elif kind == "boolean":
        if not isinstance(value, bool):
            bad("Expected a boolean")
    elif kind == "enum":
        if not isinstance(value, str) or value not in shape["values"]:
            bad("Invalid enum value")
    elif kind == "list":
        if not isinstance(value, list):
            bad("Expected a list")
        for item in value:
            if item is None:
                if not shape["nullable"]:
                    bad("Null list element")
            else:
                validate(item, shape["of"], shapes)
    elif kind == "object":
        if not isinstance(value, dict):
            bad("Expected an object")
        for name, spec in shape["fields"].items():
            present = value.get(name)
            if present is None:
                if spec["required"]:
                    bad(f"Missing field {name}")
            else:
                validate(present, spec["shape"], shapes)


def absent(name: str, options: Options) -> Any:
    if "default_value" in options:
        return options["default_value"]
    if options.get("optional"):
        return None
    return bad(f"Missing {name}")


def split_list(values: List[str]) -> List[str]:
    return [part for value in values for part in value.split(",")]


def query_params(request: Request) -> Params:
    params: Params = {}
    for name, value in parse_qsl(request.url.query, keep_blank_values=True):
        params.setdefault(name, []).append(value)
    return params


def _header_values(request: Request, name: str) -> List[str]:
    values = request.headers.getlist(name)
    return [", ".join(values)] if values else []


def path_arg(request: Request, name: str, shape: Shape) -> Any:
    return parse_scalar(request.path_params[name], shape)


def query_arg(request: Request, name: str, shape: Shape, options: Options) -> Any:
    values = query_params(request).get(name, [])
    return absent(name, options) if not values else parse_scalar(values[0], shape)


def query_list_arg(request: Request, name: str, element: Shape, options: Options) -> Any:
    values = query_params(request).get(name, [])
    return absent(name, options) if not values else [parse_scalar(v, element) for v in split_list(values)]


def header_arg(request: Request, name: str, shape: Shape, options: Options) -> Any:
    values = _header_values(request, name)
    return absent(name, options) if not values else parse_scalar(values[0], shape)


def header_list_arg(request: Request, name: str, element: Shape, options: Options) -> Any:
    values = _header_values(request, name)
    return absent(name, options) if not values else [parse_scalar(v, element) for v in split_list(values)]


def has_body(request: Request) -> bool:
    if request.headers.get("transfer-encoding") is not None:
        return True
    try:
        return int(request.headers.get("content-length", "0")) > 0
    except ValueError:
        return False


def media_type(request: Request) -> str:
    return request.headers.get("content-type", "").split(";")[0].strip().lower()


def is_json(request: Request) -> bool:
    kind = media_type(request)
    return kind == "application/json" or (kind.startswith("application/") and kind.endswith("+json"))


def is_form(request: Request) -> bool:
    return media_type(request) == "application/x-www-form-urlencoded"


def is_multipart(request: Request) -> bool:
    return media_type(request).startswith("multipart/")


async def _read_limited(request: Request) -> bytes:
    declared = request.headers.get("content-length")
    if declared is not None and declared.isdigit() and int(declared) > MAX_JSON_BODY:
        raise RestError(413, "Request body is too large")
    chunks: List[bytes] = []
    total = 0
    async for chunk in request.stream():
        total += len(chunk)
        if total > MAX_JSON_BODY:
            raise RestError(413, "Request body is too large")
        chunks.append(chunk)
    return b"".join(chunks)


async def prepare_body(request: Request) -> None:
    request.state.json = None
    request.state.text = ""
    if not has_body(request):
        return
    if is_json(request):
        raw = await _read_limited(request)
        if raw.strip():
            try:
                value = json.loads(raw)
            except ValueError:
                bad("Malformed JSON body")
            if not isinstance(value, (dict, list)):
                bad("Malformed JSON body")
            request.state.json = value
    elif is_form(request):
        request.state.text = (await _read_limited(request)).decode("utf-8", "replace")


def body_arg(request: Request, shape: Shape, shapes: Shapes, options: Options) -> Any:
    if not has_body(request):
        return absent("request body", options)
    if not is_json(request):
        raise RestError(415, "Unsupported media type")
    value = request.state.json
    if value is None:
        value = {}
    validate(value, shape, shapes)
    return value


def _child_keys(keys: List[str], name: str) -> List[str]:
    result: List[str] = []
    for key in keys:
        result.extend([name] if key == "" else [f"{key}.{name}", f"{key}[{name}]"])
    return result


def _values_of(params: Params, keys: List[str]) -> List[str]:
    return [value for key in keys for value in params.get(key, [])]


def _read_nested(params: Params, keys: List[str], shape: Shape, shapes: Shapes) -> Any:
    kind = shape["k"]
    if kind == "ref":
        return _read_nested(params, keys, shapes[shape["name"]], shapes)
    if kind == "object":
        result: Dict[str, Any] = {}
        for name, spec in shape["fields"].items():
            child = _read_nested(params, _child_keys(keys, name), spec["shape"], shapes)
            if child is not None:
                result[name] = child
        return result or None
    if kind == "list":
        element = shapes[shape["of"]["name"]] if shape["of"]["k"] == "ref" else shape["of"]
        if element["k"] not in ("object", "list"):
            values = split_list(_values_of(params, keys))
            return [parse_scalar(v, element) for v in values] if values else None
        items: List[Any] = []
        index = 0
        while True:
            item = _read_nested(params, _child_keys(keys, str(index)), shape["of"], shapes)
            if item is None:
                break
            items.append(item)
            index += 1
        return items or None
    values = _values_of(params, keys)
    return parse_scalar(values[0], shape) if values else None


def nested_arg(params: Params, name: str, shape: Shape, shapes: Shapes, options: Options) -> Any:
    value = _read_nested(params, [name], shape, shapes)
    if value is None:
        return absent(name, options)
    validate(value, shape, shapes)
    return value


def json_arg(params: Params, name: str, shape: Shape, shapes: Shapes, options: Options) -> Any:
    values = params.get(name)
    if not values:
        return absent(name, options)
    try:
        value = json.loads(values[0])
    except ValueError:
        return bad(f"Invalid JSON in {name}")
    validate(value, shape, shapes)
    return value


@dataclass
class FormFields:
    fields: Params = field(default_factory=dict)


def read_form(request: Request) -> FormFields:
    form = FormFields()
    if not has_body(request):
        return form
    if not is_form(request):
        raise RestError(415, "Expected application/x-www-form-urlencoded")
    for name, value in parse_qsl(request.state.text, keep_blank_values=True):
        form.fields.setdefault(name, []).append(value)
    return form


def form_arg(form: FormFields, name: str, shape: Shape, options: Options) -> Any:
    values = form.fields.get(name)
    return absent(name, options) if values is None else parse_scalar(values[0], shape)


def form_list_arg(form: FormFields, name: str, element: Shape, options: Options) -> Any:
    values = form.fields.get(name)
    return absent(name, options) if values is None else [parse_scalar(v, element) for v in split_list(values)]


def checked(value: Any, shape: Shape, shapes: Shapes) -> Any:
    validate(value, shape, shapes)
    return value


def send_json(value: Any) -> Response:
    if value is None:
        return Response(status_code=200)
    return JSONResponse(value)


def wrap(value: Any, path: List[str]) -> Any:
    result = value
    for key in reversed(path):
        result = {key: result}
    return result


def send_text(value: str) -> Response:
    return Response(value, status_code=200, media_type="text/plain")


def send_no_content() -> Response:
    return Response(status_code=204)


def send_error(status: int) -> Response:
    return JSONResponse({"status": status, "error": REASONS.get(status, "Error")}, status_code=status)


def handle(action: Callable[[Request], Awaitable[Response]]) -> Callable[[Request], Awaitable[Response]]:
    async def handler(request: Request) -> Response:
        try:
            await prepare_body(request)
            return await action(request)
        except RestError as error:
            return send_error(error.status)
        except Exception as error:
            print(f"REST handler failed: {error!r}", file=sys.stderr)
            return send_error(500)
        finally:
            form = getattr(request.state, "multipart", None)
            if form is not None:
                await form.close()

    return handler


def method_not_allowed(methods: List[str]) -> Callable[[Request], Awaitable[Response]]:
    async def handler(request: Request) -> Response:
        response = send_error(405)
        response.headers["Allow"] = ", ".join(methods)
        return response

    return handler


async def not_found(request: Request) -> Response:
    return send_error(404)
''';

const fastapiRestUploadsRaw = r'''
from typing import AsyncIterator

from starlette.requests import Request

from ..file_upload import FileUpload


def raw_upload_arg(request: Request) -> FileUpload:
    return FileUpload(
        filename="",
        mimetype=request.headers.get("content-type", "application/octet-stream"),
        encoding="7bit",
        open_stream=lambda: request.stream(),
    )
''';

const fastapiRestUploadsMultipart = r'''

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from starlette.datastructures import UploadFile
from starlette.exceptions import HTTPException

from .support import FormFields, Options, RestError, has_body, is_multipart

MAX_FILE_SIZE = 100 * 1024 * 1024
CHUNK = 64 * 1024


@dataclass
class MultipartForm(FormFields):
    files: Dict[str, List[FileUpload]] = field(default_factory=dict)


def _stream_of(upload: UploadFile):
    async def chunks() -> AsyncIterator[bytes]:
        await upload.seek(0)
        while True:
            chunk = await upload.read(CHUNK)
            if not chunk:
                return
            yield chunk

    return chunks


async def read_multipart(request: Request) -> MultipartForm:
    form = MultipartForm()
    if not is_multipart(request):
        if not has_body(request):
            return form
        raise RestError(415, "Expected multipart/form-data")
    try:
        parsed = await request.form()
    except HTTPException:
        raise RestError(400, "Malformed multipart body")
    except Exception:
        raise RestError(400, "Malformed multipart body")
    request.state.multipart = parsed
    for name, value in parsed.multi_items():
        if isinstance(value, UploadFile):
            if (value.size or 0) > MAX_FILE_SIZE:
                raise RestError(413, "File too large")
            form.files.setdefault(name, []).append(
                FileUpload(
                    filename=value.filename or "",
                    mimetype=value.content_type or "application/octet-stream",
                    encoding="7bit",
                    open_stream=_stream_of(value),
                )
            )
        else:
            form.fields.setdefault(name, []).append(str(value))
    return form


def _missing(name: str, options: Options) -> Any:
    if options.get("optional"):
        return None
    raise RestError(400, f"Missing {name}")


def file_arg(form: MultipartForm, name: str, options: Options) -> Any:
    files = form.files.get(name)
    return _missing(name, options) if files is None else files[0]


def file_list_arg(form: MultipartForm, name: str, options: Options) -> Any:
    files = form.files.get(name)
    return _missing(name, options) if files is None else files
''';

const fastapiRestDownload = r'''
import mimetypes
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, Union
from urllib.parse import quote

from starlette.responses import Response, StreamingResponse


@dataclass
class GraphLinkDownload:
    """What a service returns for a `@glDownload` scalar: the bytes (an iterator is streamed as is) and how to present them."""

    data: Any
    filename: Optional[str] = None
    content_type: Optional[str] = None
    length: Optional[int] = None


def _content_disposition(filename: str) -> str:
    clean = re.sub(r"[\x00-\x1f\x7f]", "_", filename)
    ascii_name = re.sub(r"[^\x20-\x7e]", "?", clean)
    ascii_name = re.sub(r'(["\\])', r"\\\1", ascii_name)
    if clean == re.sub(r'\\(["\\])', r"\1", ascii_name):
        return f'attachment; filename="{ascii_name}"'
    return f"attachment; filename=\"{ascii_name}\"; filename*=UTF-8''{quote(clean, safe='-_.!~')}"


def _with_charset(content_type: str) -> str:
    if "charset" in content_type.lower():
        return content_type
    if re.match(r"^text/|^application/(javascript|json)", content_type):
        return f"{content_type}; charset=utf-8"
    return content_type


def send_download(download: Optional[GraphLinkDownload]) -> Response:
    if download is None:
        return Response(status_code=204)
    headers: Dict[str, str] = {}
    content_type: Optional[str] = download.content_type
    if download.filename is not None:
        headers["Content-Disposition"] = _content_disposition(download.filename)
        if content_type is None:
            content_type = mimetypes.guess_type(download.filename)[0] or "application/octet-stream"
    if content_type is None:
        content_type = "application/octet-stream"
    headers["Content-Type"] = _with_charset(content_type)
    data = download.data
    if isinstance(data, str):
        data = data.encode("utf-8")
    if isinstance(data, (bytes, bytearray, memoryview)):
        return Response(bytes(data), status_code=200, headers=headers)
    if download.length is not None:
        headers["Content-Length"] = str(download.length)
    return StreamingResponse(data, status_code=200, headers=headers)
''';
