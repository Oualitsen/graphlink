#!/usr/bin/env python3
"""Stdlib-only REST server for the generated-client tests.

It is deliberately independent of GraphLink: /echo/** reports exactly what arrived on the wire
(method, raw path, query pairs, headers, decoded body), and the other routes implement small
behaviours (CRUD, counters for caching, uploads/downloads, error statuses, polymorphic JSON).
"""
import argparse
import gzip
import hashlib
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, unquote

API_PREFIX = '/api'
LOCK = threading.Lock()


def fresh_state():
    return {
        'products': {
            'p1': {'id': 'p1', 'name': 'Pen', 'price': 2.5, 'status': 'ACTIVE', 'tags': ['office', 'blue'], 'related': [{'id': 'p2', 'name': 'Book', 'price': 12.0, 'status': 'ACTIVE', 'tags': []}]},
            'p2': {'id': 'p2', 'name': 'Book', 'price': 12.0, 'status': 'ARCHIVED', 'tags': ['office']},
        },
        'avatars': {},
        'counters': {},
        'next_id': 3,
    }


STATE = fresh_state()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def blob(size):
    return bytes(i % 251 for i in range(size))


def split_multipart(body, boundary):
    delimiter = b'--' + boundary.encode()
    parts = []
    for chunk in body.split(delimiter)[1:]:
        if chunk.startswith(b'--'):
            break
        chunk = chunk[2:] if chunk.startswith(b'\r\n') else chunk
        chunk = chunk[:-2] if chunk.endswith(b'\r\n') else chunk
        raw_headers, _, content = chunk.partition(b'\r\n\r\n')
        headers = {}
        for line in raw_headers.decode('utf-8').split('\r\n'):
            if ':' in line:
                key, _, value = line.partition(':')
                headers[key.strip().lower()] = value.strip()
        disposition = headers.get('content-disposition', '')
        fields = {}
        for piece in disposition.split(';')[1:]:
            key, _, value = piece.strip().partition('=')
            fields[key] = value.strip('"')
        parts.append({
            'name': fields.get('name', ''),
            'filename': fields.get('filename'),
            'contentType': headers.get('content-type'),
            'size': len(content),
            'sha256': sha(content),
            'text': content.decode('utf-8') if 'filename' not in fields else None,
            'content': content,
        })
    return parts


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = lambda self: self.dispatch()

    def read_body(self):
        if 'chunked' in self.headers.get('Transfer-Encoding', '').lower():
            data = b''
            while True:
                size = int(self.rfile.readline().strip().split(b';')[0] or b'0', 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.read(2)
        length = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(length) if length else b''

    def send(self, status, body=b'', content_type=None, headers=None):
        self.send_response(status)
        if content_type:
            self.send_header('Content-Type', content_type)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        if status != 204:
            self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if status != 204 and self.command != 'HEAD':
            self.wfile.write(body)

    def send_json(self, status, value, headers=None):
        self.send(status, json.dumps(value, ensure_ascii=False).encode('utf-8'), 'application/json; charset=utf-8', headers)

    def dispatch(self):
        body = self.read_body()
        raw_path, _, raw_query = self.path.partition('?')
        path = raw_path[len(API_PREFIX):] if raw_path.startswith(API_PREFIX + '/') else raw_path
        segments = [unquote(s) for s in path.split('/')[1:]]
        try:
            with LOCK:
                self.route(segments, raw_path, raw_query, body)
        except Exception as e:  # noqa: BLE001
            self.send_json(500, {'error': f'server failure: {e!r}'})

    def route(self, s, raw_path, raw_query, body):
        method = self.command
        head = s[0] if s else ''
        if method == 'POST' and s == ['_reset']:
            STATE.clear()
            STATE.update(fresh_state())
            return self.send_json(200, {'ok': True})
        if method == 'POST' and s == ['_shutdown']:
            self.send_json(200, {'ok': True})
            return threading.Thread(target=self.server.shutdown, daemon=True).start()
        if s == ['gzip']:
            payload = gzip.compress(json.dumps(list(STATE['products'].values())).encode('utf-8'))
            return self.send(200, payload, 'application/json', {'Content-Encoding': 'gzip'})
        if s == ['redirect']:
            return self.send(302, b'', None, {'Location': '/count'})
        if s == ['big']:
            n = int(dict(parse_qsl(raw_query)).get('n', '1000'))
            return self.send_json(200, [{'id': f'b{i}', 'name': f'big-{i}', 'price': float(i), 'status': 'ACTIVE', 'tags': ['x', 'y']} for i in range(n)])
        if s == ['invalid-json']:
            return self.send(200, b'{not json', 'application/json')
        if s == ['html-error']:
            return self.send(500, b'<html><body>Internal Server Error</body></html>', 'text/html')
        if method == 'POST' and s == ['graphql']:
            request = json.loads(body.decode('utf-8'))
            if 'getCount' in request.get('query', ''):
                return self.send_json(200, {'data': {'getCount': 19}})
            return self.send_json(200, {'errors': [{'message': 'unknown query'}]})
        if s == ['health']:
            return self.send_json(200, {'ok': True})
        if head == 'echo':
            return self.echo(raw_path, raw_query, body)
        if head == 'status' and len(s) >= 2:
            return self.status(int(s[1]))
        if head == 'blank':
            return self.send(200)
        if head == 'nocontent':
            return self.send(204)
        if s == ['null']:
            return self.send(200, b'null', 'application/json')
        if s == ['count']:
            return self.send_json(200, 7)
        if s == ['flag']:
            return self.send_json(200, True)
        if s == ['text']:
            return self.send(200, 'héllo ✓'.encode('utf-8'), 'text/plain; charset=utf-8')
        if s == ['wrapped']:
            return self.send_json(200, {'data': {'items': list(STATE['products'].values())}, 'meta': {'total': len(STATE['products'])}})
        if s == ['deep']:
            return self.send_json(200, {'a': {'b': {'c': [1, 2, 3]}}})
        if s == ['unicode']:
            return self.send_json(200, {'id': 'u1', 'name': 'é漢😀 "quoted"', 'price': 0.0, 'status': 'ACTIVE', 'tags': ['ß']})
        if s == ['extra-keys']:
            return self.send_json(200, {'id': 'x', 'name': 'X', 'unknown': {'a': 1}, 'tags': None})
        if head == 'missing-field':
            return self.send_json(200, {'id': 'x'})
        if s == ['pets']:
            return self.send_json(200, [
                {'kind': 'dog', 'id': 'd1', 'name': 'Rex', 'barks': True},
                {'kind': 'cat', 'id': 'c1', 'name': 'Tom', 'lives': 9},
            ])
        if head == 'pets' and len(s) == 2:
            pets = {'d1': {'kind': 'dog', 'id': 'd1', 'name': 'Rex', 'barks': True}, 'c1': {'kind': 'cat', 'id': 'c1', 'name': 'Tom', 'lives': 9}}
            return self.send_json(200, pets[s[1]]) if s[1] in pets else self.send_json(404, {'error': 'no pet'})
        if s == ['pets-unknown']:
            return self.send_json(200, [{'kind': 'bird', 'id': 'b1', 'name': 'Tweety'}])
        if s == ['hits']:
            return self.send_json(200, [
                {'type': 'product', 'id': 'p1', 'name': 'Pen', 'tags': []},
                {'type': 'owner', 'id': 'o1', 'name': 'Ann'},
            ])
        if s == ['auth', 'check']:
            if self.headers.get('Authorization') != 'Bearer secret':
                return self.send_json(401, {'error': 'unauthorized'}, {'WWW-Authenticate': 'Bearer'})
            return self.send_json(200, {'user': 'ann', 'tenant': self.headers.get('X-Tenant')})
        if head == 'counter':
            return self.counter(s)
        if head == 'blob' and len(s) == 2:
            data = blob(int(s[1]))
            return self.send(200, data, 'application/octet-stream', {'Content-Disposition': f'attachment; filename="blob-{s[1]}.bin"'})
        if head == 'products':
            return self.products(s, raw_query, body)
        self.send_json(404, {'error': f'no route {method} {"/".join(s)}'})

    def echo(self, raw_path, raw_query, body):
        content_type = self.headers.get('Content-Type')
        form, parts = [], []
        mime = (content_type or '').split(';')[0].strip().lower()
        if mime == 'application/x-www-form-urlencoded':
            form = [{'name': k, 'value': v} for k, v in parse_qsl(body.decode('utf-8'), keep_blank_values=True)]
        elif mime == 'multipart/form-data':
            boundary = content_type.split('boundary=')[1].strip('"')
            parts = [{k: v for k, v in p.items() if k != 'content'} for p in split_multipart(body, boundary)]
        try:
            text = body.decode('utf-8') if len(body) <= 1_000_000 else None
        except UnicodeDecodeError:
            text = None
        self.send_json(200, {
            'method': self.command,
            'path': raw_path,
            'rawQuery': raw_query,
            'query': [{'name': k, 'value': v} for k, v in parse_qsl(raw_query, keep_blank_values=True)],
            'headers': [{'name': k.lower(), 'value': v} for k, v in self.headers.items()],
            'contentType': content_type,
            'contentLength': int(self.headers['Content-Length']) if 'Content-Length' in self.headers else None,
            'chunked': 'chunked' in self.headers.get('Transfer-Encoding', '').lower(),
            'bodyText': text,
            'bodySize': len(body),
            'bodySha256': sha(body),
            'form': form,
            'parts': parts,
        })

    def status(self, code):
        if code in (200, 201):
            return self.send_json(code, STATE['products']['p1'])
        if code == 204:
            return self.send(204)
        self.send_json(code, {'error': f'status {code}'}, {'X-Reason': f'reason-{code}'})

    def counter(self, s):
        name = s[1]
        counters = STATE['counters']
        if self.command == 'GET' and (len(s) == 2 or s[2] in ('other', 'uncached', 'nocache', 'short', 'offline')):
            counters[name] = counters.get(name, 0) + 1
            return self.send_json(200, {'name': name, 'n': counters[name]})
        if s[2:] == ['bump']:
            counters[name] = counters.get(name, 0) + 100
            return self.send_json(200, {'name': name, 'n': counters[name]})
        if s[2:] == ['reset']:
            counters.clear()
            return self.send_json(200, {'name': name, 'n': 0})
        self.send_json(404, {'error': 'no counter route'})

    def products(self, s, raw_query, body):
        products = STATE['products']
        method = self.command
        if len(s) == 1:
            if method == 'GET':
                query = parse_qsl(raw_query, keep_blank_values=True)
                tag = next((v for k, v in query if k == 'tag'), None)
                ids = [i for k, v in query if k == 'ids' for i in v.split(',')]
                result = [p for p in products.values() if (tag is None or tag in p['tags']) and (not ids or p['id'] in ids)]
                return self.send_json(200, result)
            if method == 'POST':
                data = json.loads(body.decode('utf-8'))
                pid = f"p{STATE['next_id']}"
                STATE['next_id'] += 1
                products[pid] = {'id': pid, 'name': data['name'], 'price': data.get('price'), 'status': data.get('status') or 'ACTIVE', 'tags': data.get('tags') or []}
                return self.send_json(201, products[pid], {'Location': f'/products/{pid}'})
        pid = s[1]
        product = products.get(pid)
        if len(s) == 2:
            if product is None:
                return self.send_json(404, {'error': f'no product {pid}'})
            if method == 'GET':
                return self.send_json(200, product)
            if method in ('PUT', 'PATCH'):
                product.update({k: v for k, v in json.loads(body.decode('utf-8')).items()})
                return self.send_json(200, product)
            if method == 'DELETE':
                del products[pid]
                return self.send(204)
        if product is None:
            return self.send_json(404, {'error': f'no product {pid}'})
        action = s[2]
        if action == 'rename' and method == 'POST':
            form = dict(parse_qsl(body.decode('utf-8'), keep_blank_values=True))
            product['name'] = form['name']
            if 'note' in form:
                product['tags'] = [form['note']]
            return self.send_json(200, product)
        if action == 'avatar':
            if method == 'PUT':
                STATE['avatars'][pid] = (body, self.headers.get('Content-Type', 'application/octet-stream'))
                return self.send(204)
            if method == 'GET':
                if pid not in STATE['avatars']:
                    return self.send_json(404, {'error': 'no avatar'})
                data, mime = STATE['avatars'][pid]
                return self.send(200, data, mime, {'Content-Disposition': f'attachment; filename="{pid}.png"'})
        if action == 'avatar-or-empty' and method == 'GET':
            if pid not in STATE['avatars']:
                return self.send(204)
            data, mime = STATE['avatars'][pid]
            return self.send(200, data, mime)
        if action == 'gallery' and method == 'POST':
            boundary = self.headers['Content-Type'].split('boundary=')[1].strip('"')
            parts = split_multipart(body, boundary)
            product['tags'] = [p['filename'] for p in parts if p['filename']]
            if any(p['name'] == 'title' for p in parts):
                product['name'] = next(p['text'] for p in parts if p['name'] == 'title')
            return self.send_json(200, product)
        self.send_json(404, {'error': f'no route {method} {"/".join(s)}'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9995)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.daemon_threads = True
    print(f'rest server on {args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == '__main__':
    main()
