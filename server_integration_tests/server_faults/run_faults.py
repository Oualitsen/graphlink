#!/usr/bin/env python3
"""Sends malformed and hostile requests to a generated GraphQL server.

usage: run_faults.py <server-name> <port>

A case passes when the server answers with an allowed status (never a 5xx unless
listed), reports an error where one is expected, leaks no stack trace or file path,
and still answers a valid query afterwards. Cases a server is known to fail are in
known_defects.json; a known defect that passes is itself a failure, so entries get removed.
"""
import base64
import http.client
import json
import os
import re
import socket
import struct
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
TIMEOUT = 15
LEAK = re.compile(
    r"\bat [\w$.<>]+\([\w$.]+\.(java|kt|ts|js|mjs):\d+\)"
    r"|node_modules|org\.springframework|java\.lang\.|kotlinx?\.|graphql\.GraphQLException"
    r"|/Users/|/home/runner|\.java:\d+|\.kt:\d+|\.ts:\d+"
)
PROBE = json.dumps({"query": "{ listAuthors { id } }"})


def expand(value):
    if isinstance(value, dict):
        return {k: expand(v) for k, v in value.items()}
    if isinstance(value, str):
        m = re.fullmatch(r"\{\{deep:(\d+)\}\}", value)
        if m:
            n = int(m.group(1))
            return "{ getAuthor(id: \"1\") " + "{ articles { author " * n + "{ id }" + " } }" * n + " }"
        m = re.fullmatch(r"\{\{repeat:(.):(\d+)\}\}", value)
        if m:
            return m.group(1) * int(m.group(2))
        m = re.fullmatch(r"\{\{aliases:(\d+)\}\}", value)
        if m:
            return "{ " + " ".join(f"a{i}: listAuthors {{ id }}" for i in range(int(m.group(1)))) + " }"
    return value


def request(port, method, body, content_type, path="/graphql"):
    conn = http.client.HTTPConnection("localhost", port, timeout=TIMEOUT)
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = content_type
    try:
        conn.request(method, path, body=body, headers=headers)
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8", "replace")
    finally:
        conn.close()


def alive(port):
    try:
        status, body = request(port, "POST", PROBE, "application/json")
        return status == 200 and '"listAuthors"' in body
    except Exception:
        return False


def run_http_case(case, port):
    method = case.get("method", "POST")
    content_type = case.get("contentType", "application/json")
    path = "/graphql"
    body = None
    if "rawBody" in case:
        body = case["rawBody"].encode()
    elif "body" in case:
        body = json.dumps(case["body"]).encode()
    elif "bodyTemplate" in case:
        body = json.dumps(expand(case["bodyTemplate"])).encode()
    if "query" in case:
        from urllib.parse import quote
        path += "?query=" + quote(case["query"])

    try:
        status, text = request(port, method, body, content_type, path)
    except Exception as e:
        if case.get("allowClose") and alive(port):
            return []
        return [f"no response: {type(e).__name__}: {e}"]

    problems = []
    if status not in case["status"]:
        problems.append(f"status {status}, expected one of {case['status']}")
    elif status >= 500 and status not in case["status"]:
        problems.append(f"status {status}")
    if LEAK.search(text):
        problems.append(f"response leaks internals: {LEAK.search(text).group(0)!r}")
    wants_errors = case.get("errors")
    if wants_errors == "unless400":
        wants_errors = None if status in (400, 405) else True
    if wants_errors is not None:
        try:
            doc = json.loads(text)
        except ValueError:
            doc = None
        has_errors = isinstance(doc, dict) and bool(doc.get("errors"))
        if wants_errors and not has_errors:
            problems.append(f"expected a GraphQL errors array, got: {text[:160]!r}")
        if not wants_errors and has_errors:
            problems.append(f"unexpected errors: {text[:160]!r}")
        if wants_errors and isinstance(doc, dict) and isinstance(doc.get("data"), dict) \
                and any(v is not None for v in doc["data"].values()) and status == 400:
            problems.append("400 response carries data")
    return problems


class WsClosed(Exception):
    def __init__(self, code):
        self.code = code


class Ws:
    def __init__(self, port):
        self.sock = socket.create_connection(("localhost", port), timeout=TIMEOUT)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            "GET /graphql HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
            "Sec-WebSocket-Protocol: graphql-transport-ws\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError("handshake closed")
            head += chunk
        if b" 101 " not in head.split(b"\r\n")[0] + b" ":
            raise ConnectionError(head.split(b"\r\n")[0].decode())

    def send(self, text):
        data = text.encode()
        header = bytearray([0x81])
        n = len(data)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(bytes(header) + mask + masked)

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise WsClosed(None)
            buf += chunk
        return buf

    def recv(self):
        while True:
            b1, b2 = self._read(2)
            opcode = b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(n)
            if opcode == 8:
                raise WsClosed(struct.unpack(">H", payload[:2])[0] if len(payload) >= 2 else 1005)
            if opcode == 9:
                continue
            if opcode in (1, 2):
                return payload.decode("utf-8", "replace")

    def close(self):
        self.sock.close()


def run_ws_case(case, port):
    try:
        ws = Ws(port)
    except Exception as e:
        return [f"handshake failed: {e}"]
    close_code = None
    messages = []
    try:
        for item in case["send"]:
            if item == "init":
                ws.send(json.dumps({"type": "connection_init"}))
                ws.sock.settimeout(TIMEOUT)
                messages.append(json.loads(ws.recv()))
                continue
            ws.send(item if isinstance(item, str) else json.dumps(item))
        deadline_reads = 4
        while deadline_reads:
            deadline_reads -= 1
            ws.sock.settimeout(3)
            try:
                messages.append(json.loads(ws.recv()))
            except socket.timeout:
                break
            if any(m.get("type") in ("error", "next") for m in messages):
                break
    except WsClosed as c:
        close_code = c.code
    except socket.timeout:
        pass
    except Exception as e:
        return [f"{type(e).__name__}: {e}"]
    finally:
        ws.close()

    problems = []
    got_error = any(
        isinstance(m, dict)
        and (m.get("type") == "error" or (m.get("type") == "next" and (m.get("payload") or {}).get("errors")))
        for m in messages
    )
    texts = json.dumps(messages)
    if LEAK.search(texts):
        problems.append(f"message leaks internals: {LEAK.search(texts).group(0)!r}")
    if "expectClose" in case and close_code not in case["expectClose"]:
        problems.append(f"close code {close_code}, expected {case['expectClose']}; messages {texts[:160]}")
    if "expectMessage" in case and not got_error:
        problems.append(f"expected an error message, got close={close_code} messages={texts[:160]}")
    if "expectAnyOf" in case:
        o = case["expectAnyOf"]
        if not (close_code in o.get("close", []) or (o.get("message") == "error" and got_error)):
            problems.append(f"expected close {o.get('close')} or error message; close={close_code} messages={texts[:160]}")
    return problems


def run_concurrency(port):
    results = []

    def one():
        try:
            status, text = request(port, "POST", PROBE, "application/json")
            results.append(status == 200 and '"listAuthors"' in text)
        except Exception:
            results.append(False)

    threads = [threading.Thread(target=one) for _ in range(100)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    bad = results.count(False)
    return [f"{bad} of 100 concurrent requests failed"] if bad else []


def main():
    server, port = sys.argv[1], int(sys.argv[2])
    cases = json.load(open(os.path.join(HERE, "cases.json")))
    known = json.load(open(os.path.join(HERE, "known_defects.json"))).get(server, {})
    runs = [(c["name"], c, run_http_case) for c in cases["http"]]
    runs += [(c["name"], c, run_ws_case) for c in cases["ws"]]

    failed, stale, expected = [], [], 0
    for name, case, fn in runs:
        problems = fn(case, port)
        if not alive(port):
            problems.append("SERVER NOT ANSWERING AFTER THIS CASE")
        if name in known:
            if problems:
                expected += 1
                print(f"  known   {name}: {known[name]}")
            else:
                stale.append(name)
                print(f"  STALE   {name}: passes now, remove it from known_defects.json")
        elif problems:
            failed.append(name)
            print(f"  FAIL    {name}")
            for p in problems:
                print(f"            {p}")
        else:
            print(f"  ok      {name}")
        if "SERVER NOT ANSWERING" in " ".join(problems):
            print("server is down, stopping")
            break
    problems = run_concurrency(port)
    if problems:
        failed.append("concurrency")
        print(f"  FAIL    concurrency: {problems[0]}")
    else:
        print("  ok      concurrency")

    print(f"\n{server}: {len(runs) + 1 - len(failed) - len(stale) - expected} ok, "
          f"{expected} known defects, {len(failed)} failed, {len(stale)} stale")
    sys.exit(1 if failed or stale else 0)


if __name__ == "__main__":
    main()
