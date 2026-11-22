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

    def do_GET(self):
        self.reply(200, {'ok': True}) if self.path == '/health' else self.reply(404, {})

    def do_POST(self):
        if self.path == '/_shutdown':
            self.reply(200, {})
            threading.Thread(target=self.server.shutdown).start()
            return
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        self.reply(200, run(body.get('operationName'), body.get('variables') or {}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=9930)
    ThreadingHTTPServer(('127.0.0.1', parser.parse_args().port), Handler).serve_forever()
