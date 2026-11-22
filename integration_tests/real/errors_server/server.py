#!/usr/bin/env python3
"""Stdlib-only GraphQL server for the typed-errors client tests (schema_errors/errors.graphql).

POST /graphql answers by operation name and by the `id` / `input.title` the test sends, so every language runs the same cases:

  article(id)        "1" -> data; "missing" -> ArticleNotFound{id}; "forbidden" -> Forbidden (extensions.kind);
                     "other-code" -> a code the client does not know; "no-field" -> ArticleNotFound without its `id`;
                     "no-path" -> ArticleNotFound entry without path; "no-extensions" -> plain error entry
  secret             Forbidden
  plain(id)          ArticleNotFound (the operation does not declare it)
  other(id)          data
  createArticle      title "taken" -> TitleTaken; "banned" -> Banned; else data
  pair               article fails with ArticleNotFound, other succeeds
  captured           article fails with ArticleNotFound (capture-errors operation)

REST (same server):
  GET  /items/{id}   "1" -> 200; "missing" -> 404 {id} (ItemNotFound by status); "html-404" -> 404 with an HTML body;
                     "conflict" -> 409 {code: CONFLICT, reason}; "conflict-no-reason" -> 409 without `reason`;
                     "conflict-other" -> 409 with another code; "rate" -> 429 {error: {kind: rate}, retryAfter};
                     "rate-bad" -> 429 with a string retryAfter; "teapot" -> 418 text/plain; "bad-gateway" -> 502 HTML
  GET  /plain/{id}   404 {id} (the operation does not declare it)
  POST /items        name "dup" -> 409 CONFLICT; else 201
"""
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def entry(code, path, message, **extensions):
    return {'message': message, 'path': path, 'extensions': {'code': code, **extensions}}


def article(id):
    return {'id': id, 'title': 'Title ' + id}


def fail(field, error):
    return {'data': {field: None}, 'errors': [error]}


def resolve_article(args, key):
    id = args['id']
    path = [key]
    if id == '1':
        return {'data': {key: article(id)}}
    if id == 'missing':
        return fail(key, entry('ArticleNotFound', path, 'Article missing not found', id=id))
    if id == 'forbidden':
        return fail(key, {'message': 'No access', 'path': path, 'extensions': {'code': 'X', 'kind': 'forbidden'}})
    if id == 'other-code':
        return fail(key, entry('SomethingNew', path, 'A new error', id=id))
    if id == 'no-field':
        return fail(key, entry('ArticleNotFound', path, 'Article without its id'))
    if id == 'no-path':
        return fail(key, {'message': 'No path', 'extensions': {'code': 'ArticleNotFound', 'id': id}})
    if id == 'no-extensions':
        return fail(key, {'message': 'Plain failure', 'path': path})
    return {'data': {key: article(id)}}


def run(operation, variables):
    if operation == 'article':
        return resolve_article(variables, 'article')
    if operation == 'secret':
        return fail('secret', entry('Forbidden', ['secret'], 'Not allowed', kind='forbidden'))
    if operation == 'plain':
        return fail('plain', entry('ArticleNotFound', ['plain'], 'Article not found', id=variables['id']))
    if operation == 'other':
        return {'data': {'other': article(variables['id'])}}
    if operation == 'createArticle':
        title = variables['input']['title']
        if title == 'taken':
            return fail('createArticle', entry('TitleTaken', ['createArticle'], 'Title taken', title=title, suggestions=[title + '-2']))
        if title == 'banned':
            return fail('createArticle', entry('BANNED', ['createArticle'], 'Banned', reason='SPAM', until=5))
        return {'data': {'createArticle': article(title)}}
    if operation == 'pair':
        return {'data': {'first': None, 'second': article('1')},
                'errors': [entry('ArticleNotFound', ['first'], 'Article missing not found', id='missing')]}
    if operation == 'captured':
        return fail('article', entry('ArticleNotFound', ['article'], 'Article missing not found', id='missing'))
    return {'errors': [{'message': 'Unknown operation ' + str(operation)}]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        raw = json.dumps(payload).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def raw(self, status, content_type, text):
        raw = text.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == '/health':
            self.reply(200, {'ok': True})
        elif self.path.startswith('/items/'):
            self.item(self.path[len('/items/'):])
        elif self.path.startswith('/plain/'):
            self.reply(404, {'id': self.path[len('/plain/'):]})
        else:
            self.reply(404, {})

    def item(self, id):
        if id == 'missing':
            self.reply(404, {'id': id, 'message': 'Item missing not found'})
        elif id == 'html-404':
            self.raw(404, 'text/html', '<html><body>Not Found</body></html>')
        elif id == 'conflict':
            self.reply(409, {'code': 'CONFLICT', 'reason': 'duplicate', 'message': 'Conflict'})
        elif id == 'conflict-no-reason':
            self.reply(409, {'code': 'CONFLICT'})
        elif id == 'conflict-other':
            self.reply(409, {'code': 'SOMETHING_ELSE', 'reason': 'x'})
        elif id == 'rate':
            self.reply(429, {'error': {'kind': 'rate'}, 'retryAfter': 30, 'message': 'Slow down'})
        elif id == 'rate-bad':
            self.reply(429, {'error': {'kind': 'rate'}, 'retryAfter': 'soon'})
        elif id == 'teapot':
            self.raw(418, 'text/plain', 'short and stout')
        elif id == 'bad-gateway':
            self.raw(502, 'text/html', '<html>Bad Gateway</html>')
        else:
            self.reply(200, {'id': id, 'name': 'Item ' + id})

    def do_POST(self):
        if self.path == '/_shutdown':
            self.reply(200, {})
            threading.Thread(target=self.server.shutdown).start()
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        if self.path == '/items':
            if body.get('name') == 'dup':
                self.reply(409, {'code': 'CONFLICT', 'reason': 'name taken', 'message': 'Conflict'})
            else:
                self.reply(201, {'id': 'new', 'name': body.get('name')})
            return
        self.reply(200, run(body.get('operationName'), body.get('variables') or {}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9930)
    ThreadingHTTPServer(('127.0.0.1', parser.parse_args().port), Handler).serve_forever()
