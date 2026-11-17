#!/usr/bin/env python3
"""Stdlib-only fault-injection server for the generated-client tests.

A test arms one fault with POST /_arm?fault=<name>; the next request to any other path gets that
fault instead of a normal answer, then the server is back to normal. Unarmed, it answers only what
the tests need to prove a client still works afterwards: POST /graphql (getCount), GET /count,
GET /status/{code}.

It also speaks graphql-transport-ws on any path (a `counterTick` subscription answers `next(1)` then `complete`).
Like the Spring test server it serves `labelTicks`, `secureTicks` (needs `Authorization: Bearer` in the connection_init
payload), their `*Starts` queries and the `Ack-Delay` connection_init payload key, so the reconnect tests can kill and start
this process in place of the JAR. `--live` makes `counterTick` tick every second until the client leaves.
POST /_arm?fault=ws-...&times=N makes the next N WebSocket connections misbehave; GET /_ws_log lists every
connection with the frames the client sent.
"""
import argparse
import base64
import hashlib
import json
import re
import socketserver
import struct
import sys
import threading
import time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit

GRAPHQL_OK = {'data': {'getCount': 19}}
PRODUCT_OK = {'id': 'p1', 'name': 'Pen', 'price': 2.5, 'status': 'ACTIVE', 'tags': ['office']}
STATE = {'armed': None, 'served': [], 'ws_armed': None, 'ws_times': 0, 'ws_log': [], 'starts': {}}
LIVE = {'counter': False}
LOCK = threading.Lock()


class Ctx:
    def __init__(self, kind, path):
        self.kind = kind
        self.path = path

    @property
    def is_product(self):
        return self.path.startswith('/status/')

    def scalar(self, raw):
        """`raw` is JSON text for the Int the operation returns."""
        return '{"data":{"getCount":%s}}' % raw if self.kind == 'graphql' else raw

    def ok_text(self):
        if self.kind == 'graphql':
            return json.dumps(GRAPHQL_OK)
        return json.dumps(PRODUCT_OK if self.is_product else 7)


def response(status=200, body='', content_type='application/json', headers=(), declared_length=None, close=False,
             delay=0.0, delay_mid_body=0.0, split_at=None):
    raw = body if isinstance(body, bytes) else body.encode('utf-8')
    return dict(status=status, body=raw, content_type=content_type, headers=list(headers),
                declared_length=declared_length, close=close, delay=delay, delay_mid_body=delay_mid_body, split_at=split_at)


def graphql_only(build):
    def wrapped(ctx):
        return build(ctx) if ctx.kind == 'graphql' else None
    return wrapped


HUGE_CASE = json.loads((Path(__file__).parent / 'huge_case.json').read_text())
HUGE_BODY = []


def huge_users_body():
    if not HUGE_BODY:
        statuses = ('ACTIVE', 'INACTIVE', 'SUSPENDED')
        users = [{
            'id': f'user-{i}',
            'name': f'User {i} Ünï 日本',
            'email': f'user-{i}@example.com',
            'status': statuses[i % 3],
            'tags': ['alpha', 'beta'],
            'address': {'street': '1 Long Street', 'city': 'Paris', 'country': 'FR', 'zip': None},
        } for i in range(HUGE_CASE['users'])]
        body = json.dumps({'data': {'bigUsers': users}}, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        assert len(body) >= HUGE_CASE['minBytes'], len(body)
        HUGE_BODY.append(body)
    return HUGE_BODY[0]


HTML = '<html><body><h1>502 Bad Gateway</h1></body></html>'
BOM = b'\xef\xbb\xbf'

FAULTS = {
    'html-502': lambda c: response(502, HTML, 'text/html'),
    'html-200': lambda c: response(200, HTML, 'text/html'),
    'plain-500': lambda c: response(500, 'upstream exploded', 'text/plain'),
    'empty-200': lambda c: response(200, ''),
    'truncated-json': lambda c: response(200, c.ok_text()[:-3]),
    'short-body': lambda c: response(200, c.ok_text()[:6], declared_length=len(c.ok_text()), close=True),
    'closed-after-headers': lambda c: response(200, '', declared_length=64, close=True),
    'bom': lambda c: response(200, BOM + c.ok_text().encode('utf-8')),
    'utf16le-bom': lambda c: response(200, b'\xff\xfe' + c.ok_text().encode('utf-16-le')),
    'utf16be-bom': lambda c: response(200, b'\xfe\xff' + c.ok_text().encode('utf-16-be')),
    'utf16-charset': lambda c: response(200, c.ok_text().encode('utf-16'), 'application/json; charset=utf-16'),
    'utf32le-bom': lambda c: response(200, b'\xff\xfe\x00\x00' + c.ok_text().encode('utf-32-le')),
    'trailing-whitespace': lambda c: response(200, c.ok_text() + '\n \r\n\t '),
    'leading-whitespace': lambda c: response(200, ' \n' + c.ok_text()),
    'text-plain-json': lambda c: response(200, c.ok_text(), 'text/plain'),
    'no-content-type': lambda c: response(200, c.ok_text(), None),
    'latin1-charset': lambda c: response(200, c.ok_text(), 'application/json; charset=iso-8859-1'),
    'wrong-charset': lambda c: response(200, c.ok_text(), 'application/json; charset=nonsense'),
    'json-array-top-level': lambda c: response(200, '[1,2,3]'),
    'json-string-top-level': lambda c: response(200, '"hello"'),
    'json-null-top-level': lambda c: response(200, 'null'),
    'int-overflow': lambda c: response(200, c.scalar('99999999999999999999999')),
    'int-exponent': lambda c: response(200, c.scalar('1e3')),
    'int-as-float': lambda c: response(200, c.scalar('19.0')),
    'int-fraction': lambda c: response(200, c.scalar('19.5')),
    'int-as-string': lambda c: response(200, c.scalar('"19"')),
    'int-bool': lambda c: response(200, c.scalar('true')),
    'int-null': lambda c: response(200, c.scalar('null')),
    'int-object': lambda c: response(200, c.scalar('{"a":1}')),
    'int-negative-zero': lambda c: response(200, c.scalar('-0')),
    'duplicate-keys': lambda c: response(200, '{"id":"first","id":"second","name":"Pen","price":2.5}'
                                         if c.is_product else '{"data":{"getCount":1,"getCount":19}}'),
    'redirect-no-location': lambda c: response(302, ''),
    'status-205': lambda c: response(205, ''),
    'status-304': lambda c: response(304, ''),
    'status-401-json': lambda c: response(401, '{"error":"unauthorized"}'),
    'status-503-retry-after': lambda c: response(503, '{"error":"busy"}', headers=[('Retry-After', '30')]),
    'repeated-headers': lambda c: response(200, c.ok_text(), headers=[('X-Dup', 'one'), ('x-dup', 'two'), ('Set-Cookie', 'a=1'), ('Set-Cookie', 'b=2')]),
    'slow': lambda c: response(200, c.ok_text(), delay=1.0),
    'huge-users': graphql_only(lambda c: response(200, huge_users_body())),
    'slow-body': lambda c: response(200, c.ok_text(), delay_mid_body=1.0, split_at=4),
    'hang': lambda c: response(200, c.ok_text(), delay=30.0),
    'gql-errors-only': graphql_only(lambda c: response(200, '{"errors":[{"message":"boom","path":["getCount"],"extensions":{"code":"BAD"}}]}')),
    'gql-null-data': graphql_only(lambda c: response(200, '{"data":null,"errors":[{"message":"cannot be null","path":["getCount"]}]}')),
    'gql-data-and-errors': graphql_only(lambda c: response(200, '{"data":{"getCount":19},"errors":[{"message":"partial"}]}')),
    'gql-null-field-with-errors': graphql_only(lambda c: response(200, '{"data":{"getCount":null},"errors":[{"message":"non-null violated","path":["getCount"]}]}')),
    'gql-missing-field': graphql_only(lambda c: response(200, '{"data":{}}')),
    'gql-data-not-object': graphql_only(lambda c: response(200, '{"data":"nope"}')),
    'gql-errors-not-list': graphql_only(lambda c: response(200, '{"errors":"boom"}')),
    'gql-empty-errors': graphql_only(lambda c: response(200, '{"data":{"getCount":19},"errors":[]}')),
    'gql-empty-object': graphql_only(lambda c: response(200, '{}')),
    'gql-500-graphql-body': graphql_only(lambda c: response(500, '{"errors":[{"message":"server down"}]}')),
    'gql-400-graphql-body': graphql_only(lambda c: response(400, '{"errors":[{"message":"bad query"}]}')),
    'gql-extra-fields': graphql_only(lambda c: response(200, '{"data":{"getCount":19,"unrequested":{"a":1}},"extensions":{"tracing":[1]}}')),
    'product-missing-field': lambda c: response(200, '{"id":"p1"}') if c.is_product else None,
    'product-wrong-type': lambda c: response(200, '{"id":"p1","name":42,"price":"x"}') if c.is_product else None,
    'product-unknown-enum': lambda c: response(200, '{"id":"p1","name":"Pen","status":"NOPE"}') if c.is_product else None,
    'product-null-id': lambda c: response(200, '{"id":null,"name":"Pen"}') if c.is_product else None,
    'product-huge-string': lambda c: response(200, json.dumps({**PRODUCT_OK, 'name': 'x' * 1_000_000})) if c.is_product else None,
    'product-deep-nesting': lambda c: response(200, json.dumps({**PRODUCT_OK, 'related': [{'id': 'r', 'name': 'r'}] * 3})) if c.is_product else None,
}


WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
WS_FAULTS = ('ws-no-ack', 'ws-invalid-json', 'ws-unknown-type', 'ws-next-unknown-id', 'ws-next-after-complete',
             'ws-error-message', 'ws-ping', 'ws-close-4400', 'ws-close-4401', 'ws-close-4403', 'ws-close-4409',
             'ws-close-4429', 'ws-close-4500', 'ws-close-1011', 'ws-abrupt', 'ws-binary')


def ws_frame(opcode, payload=b''):
    head = bytes([0x80 | opcode])
    size = len(payload)
    if size < 126:
        head += bytes([size])
    elif size < 65536:
        head += bytes([126]) + struct.pack('>H', size)
    else:
        head += bytes([127]) + struct.pack('>Q', size)
    return head + payload


def ws_text(value):
    return ws_frame(1, (value if isinstance(value, str) else json.dumps(value)).encode('utf-8'))


def ws_close(code):
    return ws_frame(8, struct.pack('>H', code))


def ws_read(rfile):
    """Next (opcode, payload) from the client, or None when the peer is gone."""
    head = rfile.read(2)
    if len(head) < 2:
        return None
    opcode, size = head[0] & 0x0F, head[1] & 0x7F
    if size == 126:
        size = struct.unpack('>H', rfile.read(2))[0]
    elif size == 127:
        size = struct.unpack('>Q', rfile.read(8))[0]
    mask = rfile.read(4) if head[1] & 0x80 else b''
    payload = rfile.read(size)
    if mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def ws_next(sub_id, value):
    return {'id': sub_id, 'type': 'next', 'payload': {'data': {'counterTick': value}}}


def operation(payload):
    match = re.match(r'\s*(?:query|subscription)\s+(\w+)', (payload or {}).get('query', ''))
    return match.group(1) if match else None


def count_start(key):
    with LOCK:
        STATE['starts'][key] = STATE['starts'].get(key, 0) + 1


def bearer(authorization):
    prefix = 'Bearer '
    if not isinstance(authorization, str) or not authorization.startswith(prefix) or len(authorization) == len(prefix):
        return None
    return authorization[len(prefix):]


def start_stream(op, payload, sub_id, auth, send, streams):
    """Starts the Spring-like ticking subscription `op`; False when the fault server has no such stream."""
    variables = payload.get('variables') or {}
    if op == 'labelTicks':
        label, count, interval = variables['label'], int(variables['count']), 0.1
        count_start(f'label:{label}')
        value = lambda i: label + '-' + str(i)
    elif op == 'secureTicks':
        token = bearer(auth)
        if token is None:
            send(ws_text({'id': sub_id, 'type': 'error', 'payload': [{'message': 'unauthenticated'}]}))
            return True
        count, interval = int(variables['count']), 0.1
        count_start(f'secure:{token}')
        value = lambda i: i
    elif op == 'counterTick' and LIVE['counter']:
        count, interval = 1 << 30, 1.0
        value = lambda i: i
    else:
        return False
    stop = threading.Event()
    streams[sub_id] = stop

    def tick():
        for i in range(1, count + 1):
            if stop.wait(interval):
                return
            try:
                send(ws_text({'id': sub_id, 'type': 'next', 'payload': {'data': {op: value(i)}}}))
            except OSError:
                return
        try:
            send(ws_text({'id': sub_id, 'type': 'complete'}))
        except OSError:
            pass

    threading.Thread(target=tick, daemon=True).start()
    return True


def ws_serve(handler):
    key = handler.headers.get('Sec-WebSocket-Key', '')
    accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
    with LOCK:
        fault = None
        if STATE['ws_armed'] and STATE['ws_times'] > 0:
            fault = STATE['ws_armed']
            STATE['ws_times'] -= 1
            if STATE['ws_times'] == 0:
                STATE['ws_armed'] = None
        log = {'conn': len(STATE['ws_log']) + 1, 'fault': fault or 'ok', 'frames': []}
        STATE['ws_log'].append(log)
    handler.send_response(101)
    handler.send_header('Upgrade', 'websocket')
    handler.send_header('Connection', 'Upgrade')
    handler.send_header('Sec-WebSocket-Accept', accept)
    if 'graphql-transport-ws' in handler.headers.get('Sec-WebSocket-Protocol', ''):
        handler.send_header('Sec-WebSocket-Protocol', 'graphql-transport-ws')
    handler.end_headers()
    handler.close_connection = True
    sock, rfile = handler.connection, handler.rfile

    send_lock = threading.Lock()
    streams = {}

    def send(data):
        with send_lock:
            sock.sendall(data)

    try:
        ws_loop(rfile, sock, send, fault, log, streams)
    finally:
        for stop in streams.values():
            stop.set()


def ws_loop(rfile, sock, send, fault, log, streams):
    auth = None
    while True:
        try:
            frame = ws_read(rfile)
        except (OSError, ValueError):
            return
        if frame is None:
            return
        opcode, payload = frame
        if opcode == 8:
            log['frames'].append({'type': 'close'})
            try:
                send(ws_close(1000))
            except OSError:
                pass
            return
        if opcode == 9:
            send(ws_frame(10, payload))
            continue
        if opcode != 1:
            log['frames'].append({'type': 'binary' if opcode == 2 else f'opcode-{opcode}'})
            continue
        try:
            message = json.loads(payload.decode('utf-8'))
        except ValueError:
            log['frames'].append({'type': 'invalid'})
            continue
        kind, sub_id = message.get('type'), message.get('id')
        log['frames'].append({'type': kind, 'id': sub_id})
        if kind == 'connection_init':
            if fault == 'ws-no-ack':
                continue
            init = message.get('payload') or {}
            auth = init.get('Authorization')
            if init.get('Ack-Delay'):
                time.sleep(int(init['Ack-Delay']) / 1000)
            send(ws_text({'type': 'connection_ack'}))
            if fault == 'ws-ping':
                send(ws_text({'type': 'ping'}))
        elif kind == 'subscribe':
            if fault is None and start_stream(operation(message.get('payload')), message['payload'], sub_id, auth, send, streams):
                continue
            if ws_fault_on_subscribe(fault, sock, send, sub_id):
                return
            send(ws_text(ws_next(sub_id, 1)))
            send(ws_text({'id': sub_id, 'type': 'complete'}))
            if fault == 'ws-next-after-complete':
                send(ws_text(ws_next(sub_id, 2)))
        elif kind == 'complete' and sub_id in streams:
            streams.pop(sub_id).set()
        elif kind == 'ping':
            send(ws_text({'type': 'pong'}))


def ws_fault_on_subscribe(fault, sock, send, sub_id):
    """Sends the fault's frames; True when the connection is over."""
    if fault == 'ws-invalid-json':
        send(ws_text('{not json'))
    elif fault == 'ws-unknown-type':
        send(ws_text({'type': 'mystery', 'id': sub_id}))
    elif fault == 'ws-next-unknown-id':
        send(ws_text(ws_next('no-such-id', 99)))
    elif fault == 'ws-binary':
        send(ws_frame(2, b'\x00\x01\x02\xff'))
    elif fault == 'ws-error-message':
        send(ws_text({'id': sub_id, 'type': 'error', 'payload': [{'message': 'boom'}]}))
        return True
    elif fault and fault.startswith('ws-close-'):
        send(ws_close(int(fault.rsplit('-', 1)[1])))
        return True
    elif fault == 'ws-abrupt':
        sock.shutdown(2)
        return True
    return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = lambda self: self.dispatch()

    def drain(self):
        length = int(self.headers.get('Content-Length') or 0)
        if length:
            return self.rfile.read(length)
        elif 'chunked' in self.headers.get('Transfer-Encoding', '').lower():
            while True:
                size = int(self.rfile.readline().strip().split(b';')[0] or b'0', 16)
                if size == 0:
                    self.rfile.readline()
                    return
                self.rfile.read(size + 2)

    def starts_answer(self, body):
        try:
            request = json.loads(body or b'{}')
        except ValueError:
            return None
        op, variables = operation(request), request.get('variables') or {}
        prefix = {'labelTickStarts': ('label', 'label'), 'secureTickStarts': ('secure', 'token')}.get(op)
        if prefix is None:
            return None
        with LOCK:
            count = STATE['starts'].get(f'{prefix[0]}:{variables[prefix[1]]}', 0)
        return {'data': {op: count}}

    def reply_json(self, status, value):
        self.reply(response(status, json.dumps(value)))

    def reply(self, spec):
        if spec['delay']:
            time.sleep(spec['delay'])
        self.send_response(spec['status'])
        if spec['content_type']:
            self.send_header('Content-Type', spec['content_type'])
        for key, value in spec['headers']:
            self.send_header(key, value)
        if spec['status'] not in (204, 304):
            declared = spec['declared_length'] if spec['declared_length'] is not None else len(spec['body'])
            self.send_header('Content-Length', str(declared))
        self.end_headers()
        body = spec['body']
        if spec['split_at'] is not None:
            self.wfile.write(body[:spec['split_at']])
            self.wfile.flush()
            time.sleep(spec['delay_mid_body'])
            body = body[spec['split_at']:]
        if body and self.command != 'HEAD':
            self.wfile.write(body)
            self.wfile.flush()
        if spec['close']:
            self.close_connection = True
            self.connection.shutdown(2)

    def dispatch(self):
        if self.headers.get('Upgrade', '').lower() == 'websocket':
            return ws_serve(self)
        body = self.drain()
        url = urlsplit(self.path)
        path = url.path
        if path == '/health':
            return self.reply_json(200, {'ok': True})
        if self.command == 'POST' and path == '/_shutdown':
            self.reply_json(200, {'ok': True})
            return threading.Thread(target=self.server.shutdown, daemon=True).start()
        if self.command == 'POST' and path == '/_arm':
            query = dict(parse_qsl(url.query))
            name = query.get('fault', '')
            if name in WS_FAULTS:
                with LOCK:
                    STATE['ws_armed'], STATE['ws_times'] = name, int(query.get('times', '1'))
                return self.reply_json(200, {'armed': name})
            if name not in FAULTS:
                return self.reply_json(400, {'error': f'unknown fault {name!r}', 'known': sorted(FAULTS) + list(WS_FAULTS)})
            with LOCK:
                STATE['armed'] = name
            return self.reply_json(200, {'armed': name})
        if self.command == 'POST' and path == '/_reset':
            with LOCK:
                STATE['armed'] = None
                STATE['ws_armed'], STATE['ws_times'] = None, 0
                STATE['served'].clear()
                STATE['ws_log'].clear()
            return self.reply_json(200, {'ok': True})
        if path == '/_ws_log':
            return self.reply_json(200, STATE['ws_log'])
        if path == '/_served':
            return self.reply_json(200, STATE['served'])

        kind = 'graphql' if self.command == 'POST' and path.rstrip('/').endswith('/graphql') else 'rest'
        started = kind == 'graphql' and not STATE['armed'] and self.starts_answer(body)
        if started is not None and started is not False:
            return self.reply_json(200, started)
        ctx = Ctx(kind, path)
        with LOCK:
            name, STATE['armed'] = STATE['armed'], None
            STATE['served'].append(name or 'ok')
        spec = FAULTS[name](ctx) if name else None
        if spec is None:
            return self.reply(response(200, ctx.ok_text()))
        self.reply(spec)


class Server(ThreadingHTTPServer):
    request_queue_size = 128
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[0], self.server_address[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9960)
    parser.add_argument('--live', action='store_true')
    args = parser.parse_args()
    LIVE['counter'] = args.live
    server = Server(('127.0.0.1', args.port), Handler)
    print(f'fault server on {args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == '__main__':
    main()
