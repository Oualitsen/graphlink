#!/usr/bin/env python3
"""Stdlib-only fault-injection server for the generated-client tests.

A test arms one fault with POST /_arm?fault=<name>; the next request to any other path gets that
fault instead of a normal answer, then the server is back to normal. Unarmed, it answers only what
the tests need to prove a client still works afterwards: POST /graphql (getCount), GET /count,
GET /status/{code}.
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit

GRAPHQL_OK = {'data': {'getCount': 19}}
PRODUCT_OK = {'id': 'p1', 'name': 'Pen', 'price': 2.5, 'status': 'ACTIVE', 'tags': ['office']}
STATE = {'armed': None, 'served': []}
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


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = lambda self: self.dispatch()

    def drain(self):
        length = int(self.headers.get('Content-Length') or 0)
        if length:
            self.rfile.read(length)
        elif 'chunked' in self.headers.get('Transfer-Encoding', '').lower():
            while True:
                size = int(self.rfile.readline().strip().split(b';')[0] or b'0', 16)
                if size == 0:
                    self.rfile.readline()
                    return
                self.rfile.read(size + 2)

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
        self.drain()
        url = urlsplit(self.path)
        path = url.path
        if path == '/health':
            return self.reply_json(200, {'ok': True})
        if self.command == 'POST' and path == '/_shutdown':
            self.reply_json(200, {'ok': True})
            return threading.Thread(target=self.server.shutdown, daemon=True).start()
        if self.command == 'POST' and path == '/_arm':
            name = dict(parse_qsl(url.query)).get('fault', '')
            if name not in FAULTS:
                return self.reply_json(400, {'error': f'unknown fault {name!r}', 'known': sorted(FAULTS)})
            with LOCK:
                STATE['armed'] = name
            return self.reply_json(200, {'armed': name})
        if self.command == 'POST' and path == '/_reset':
            with LOCK:
                STATE['armed'] = None
                STATE['served'].clear()
            return self.reply_json(200, {'ok': True})
        if path == '/_served':
            return self.reply_json(200, STATE['served'])

        kind = 'graphql' if self.command == 'POST' and path.rstrip('/').endswith('/graphql') else 'rest'
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9960)
    args = parser.parse_args()
    server = Server(('127.0.0.1', args.port), Handler)
    print(f'fault server on {args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == '__main__':
    main()
