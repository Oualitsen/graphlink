import hashlib
import json
import re
import threading
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import List, Optional


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass
class ReceivedPart:
    name: str
    filename: Optional[str]
    content_type: Optional[str]
    data: bytes

    @property
    def sha256(self) -> str:
        return sha256_of(self.data)

    @property
    def text(self) -> str:
        return self.data.decode("utf-8")


@dataclass
class Received:
    content_length: Optional[int]
    chunked: bool
    parts: List[ReceivedPart]

    def part(self, name: str) -> ReceivedPart:
        return next(p for p in self.parts if p.name == name)


class RecordingServer:
    """GraphQL endpoint that records every multipart request as it arrived on the wire."""

    def __init__(self) -> None:
        self.requests: List[Received] = []
        requests = self.requests

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self) -> None:
                chunked = "chunked" in self.headers.get("Transfer-Encoding", "").lower()
                length = self.headers.get("Content-Length")
                body = self._read_chunked() if chunked else self.rfile.read(int(length or 0))
                match = re.search(r"boundary=([^;]+)", self.headers.get("Content-Type", ""))
                requests.append(
                    Received(int(length) if length is not None else None, chunked, _parse(body, match.group(1)) if match else [])
                )
                response = json.dumps({"data": {"uploadOneFile": True, "uploadFileList": True}}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)

            def _read_chunked(self) -> bytes:
                out = bytearray()
                while True:
                    size = int(self.rfile.readline().strip().split(b";")[0], 16)
                    if size == 0:
                        self.rfile.readline()
                        return bytes(out)
                    out += self.rfile.read(size)
                    self.rfile.readline()

            def log_message(self, *_args: object) -> None:
                pass

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self._server.server_address[1]}/graphql"

    def only(self) -> Received:
        assert len(self.requests) == 1, f"expected one request, got {len(self.requests)}"
        return self.requests[0]

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()


def _parse(body: bytes, boundary: str) -> List[ReceivedPart]:
    delimiter = f"--{boundary}".encode()
    starts = [m.start() for m in re.finditer(re.escape(delimiter), body)]
    parts = []
    for i in range(len(starts) - 1):
        start = starts[i] + len(delimiter) + 2
        end = starts[i + 1] - 2
        head_end = body.index(b"\r\n\r\n", start)
        headers = body[start:head_end].decode("utf-8", errors="replace")
        disposition = re.search(r'name="([^"]*)"(?:; filename="([^"]*)")?', headers)
        content_type = re.search(r"(?i)content-type: ([^\r\n]+)", headers)
        parts.append(
            ReceivedPart(
                disposition.group(1),
                disposition.group(2),
                content_type.group(1) if content_type else None,
                body[head_end + 4 : end],
            )
        )
    return parts
