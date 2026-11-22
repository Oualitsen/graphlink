#!/usr/bin/env python3
"""Typed domain errors over raw HTTP: usage run_errors.py <server-name> <port>

The service of schema_errors/errors.gql throws the generated error classes; each case pins the wire shape the clients
of the typed-errors feature match (GraphQL `errors` entry, REST status and body). A plain exception must stay an
internal error that leaks nothing.
"""
import http.client
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEAK = re.compile(r"\bat [\w$.<>]+\([\w$.]+\.(java|kt|ts|js|mjs):\d+\)|node_modules|org\.springframework|java\.lang\.|/Users/|/home/runner")


def call(port, method, path, body=None):
    conn = http.client.HTTPConnection("localhost", port, timeout=20)
    try:
        headers = {"Content-Type": "application/json"} if body is not None else {}
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        return response.status, response.read().decode("utf-8", "replace")
    finally:
        conn.close()


def subset(expected, actual):
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(k in actual and subset(v, actual[k]) for k, v in expected.items())
    return expected == actual


def check(port, case):
    if case["protocol"] == "graphql":
        status, text = call(port, "POST", "/graphql", json.dumps({"query": case["query"]}))
    else:
        status, text = call(port, "GET", case["path"])
    if status != case["status"]:
        return f"status {status}, expected {case['status']}: {text[:200]}"
    if LEAK.search(text):
        return f"leaks internals: {text[:200]}"
    try:
        body = json.loads(text)
    except ValueError:
        return f"body is not JSON: {text[:200]}"
    if case["protocol"] == "graphql":
        errors = body.get("errors") or []
        if "data" in case:
            return None if body.get("data") == case["data"] and not errors else f"unexpected body {text[:200]}"
        if not errors:
            return f"no error in {text[:200]}"
        entry = errors[0]
        if case.get("internal"):
            code = (entry.get("extensions") or {}).get("code")
            return None if code in (None, "INTERNAL_SERVER_ERROR") else f"expected an internal error, got {entry}"
        if not subset(case["error"], entry):
            return f"entry {entry} does not contain {case['error']}"
        return None
    if case.get("internal"):
        return None
    if "json" in case and body != case["json"]:
        return f"body {body}, expected {case['json']}"
    if "jsonSubset" in case and not subset(case["jsonSubset"], body):
        return f"body {body} does not contain {case['jsonSubset']}"
    for key in case.get("absent", []):
        if key in body:
            return f"body has {key}: {body}"
    return None


def main():
    name, port = sys.argv[1], int(sys.argv[2])
    cases = json.load(open(os.path.join(HERE, "cases.json")))
    failed = 0
    for case in cases:
        problem = check(port, case)
        print(("FAIL " if problem else "ok   ") + case["name"] + (f": {problem}" if problem else ""))
        failed += bool(problem)
    print(f"{name}: {len(cases) - failed}/{len(cases)} typed-error cases passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
