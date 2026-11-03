import argparse
import hashlib
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

last = {}
lock = threading.Lock()


def parse(body, boundary):
    delimiter = ("--" + boundary).encode()
    starts = [m.start() for m in re.finditer(re.escape(delimiter), body)]
    parts = []
    for i in range(len(starts) - 1):
        start = starts[i] + len(delimiter) + 2
        end = starts[i + 1] - 2
        head_end = body.index(b"\r\n\r\n", start)
        headers = body[start:head_end].decode("utf-8", errors="replace")
        disposition = re.search(r'name="([^"]*)"(?:; filename="([^"]*)")?', headers)
        content_type = re.search(r"(?i)content-type: ([^\r\n]+)", headers)
        data = body[head_end + 4 : end]
        parts.append(
            {
                "name": disposition.group(1),
                "filename": disposition.group(2),
                "contentType": content_type.group(1) if content_type else None,
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "text": data.decode("utf-8", errors="replace") if len(data) < 4096 else None,
            }
        )
    return parts


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_chunked(self):
        out = bytearray()
        while True:
            size = int(self.rfile.readline().strip().split(b";")[0], 16)
            if size == 0:
                self.rfile.readline()
                return bytes(out)
            out += self.rfile.read(size)
            self.rfile.readline()

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True})
        elif self.path == "/_last":
            with lock:
                self._send(200, last)
        else:
            self._send(404, {})

    def do_POST(self):
        if self.path == "/_shutdown":
            self._send(200, {})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        chunked = "chunked" in self.headers.get("Transfer-Encoding", "").lower()
        length = self.headers.get("Content-Length")
        body = self._read_chunked() if chunked else self.rfile.read(int(length or 0))
        match = re.search(r"boundary=([^;]+)", self.headers.get("Content-Type", ""))
        with lock:
            last.clear()
            last.update(
                {
                    "contentLength": int(length) if length is not None else None,
                    "chunked": chunked,
                    "parts": parse(body, match.group(1)) if match else [],
                }
            )
        self._send(200, {"data": {"uploadOneFile": True, "uploadFileList": True}})

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9970)
    ThreadingHTTPServer(("127.0.0.1", parser.parse_args().port), Handler).serve_forever()
