"""Checks that what a server sends matches the OpenAPI document it serves.

Loaded by server_rest/run_rest.py: every successful REST response is validated against the response schema of the operation
its method and path belong to. Needs `jsonschema`; without it the check is skipped unless REQUIRE_OPENAPI_CONFORMANCE=1.
"""
import http.client
import json
import os
import re

try:
    from jsonschema import Draft202012Validator
except ImportError:
    Draft202012Validator = None

REQUIRED = os.environ.get("REQUIRE_OPENAPI_CONFORMANCE") == "1"
METHODS = {"get", "put", "post", "delete", "patch"}


def media_matches(actual, documented):
    actual = actual.split(";")[0].strip().lower()
    for pattern in documented:
        pattern = pattern.lower()
        if pattern == "*/*" or pattern == actual or (pattern.endswith("/*") and actual.startswith(pattern[:-1])):
            return True
    return False


class Conformance:
    def __init__(self, spec):
        self.spec = spec
        self.routes = []
        for template, item in spec["paths"].items():
            regex = re.compile("^" + re.sub(r"\\\{[^/]*?\\\}", "[^/]+", re.escape(template)) + "$")
            for method, op in item.items():
                if method in METHODS:
                    self.routes.append((method, regex, template, op, template.count("{")))

    def operation(self, method, path):
        path = path.split("?")[0]
        found = [r for r in self.routes if r[0] == method.lower() and r[1].match(path)]
        if not found:
            return None
        return min(found, key=lambda r: r[4])

    def response_spec(self, op, status):
        entry = op["responses"].get(str(status))
        if entry is None:
            return None
        if "$ref" in entry:
            node = self.spec
            for part in entry["$ref"][2:].split("/"):
                node = node[part]
            return node
        return entry

    def check(self, method, path, status, content_type, text):
        if status >= 300:
            return []
        route = self.operation(method, path)
        if route is None:
            return [f"openapi: {method} {path} matches no path of the spec"]
        _, _, template, op, _ = route
        entry = self.response_spec(op, status)
        if entry is None:
            return [f"openapi: {op['operationId']} ({template}) does not describe a {status} response"]
        content = entry.get("content", {})
        if not content:
            return [f"openapi: {op['operationId']} sends a {status} body but the spec says it has none"] if text.strip() else []
        if not text.strip():
            only_strings = all(s["schema"].get("type") == "string" for s in content.values())
            return [] if "204" in op["responses"] or only_strings else [f"openapi: {op['operationId']} sent an empty {status} body"]
        if not media_matches(content_type, content):
            return [f"openapi: {op['operationId']} content type {content_type!r} is not one of {list(content)}"]
        schema = next((s["schema"] for m, s in content.items() if media_matches(content_type, [m])), None)
        if schema is None or schema.get("format") == "binary" or "json" not in content_type:
            return []
        try:
            value = json.loads(text)
        except ValueError:
            return [f"openapi: {op['operationId']} body is not JSON"]
        validator = Draft202012Validator({**schema, "components": self.spec["components"]})
        errors = sorted(validator.iter_errors(value), key=lambda e: list(e.path))
        return [f"openapi: {op['operationId']} {status} body breaks the spec at /{'/'.join(map(str, e.path))}: {e.message[:140]}" for e in errors[:3]]


def load(port):
    if Draft202012Validator is None:
        if REQUIRED:
            raise SystemExit("REQUIRE_OPENAPI_CONFORMANCE=1 but jsonschema is not installed")
        print("openapi conformance skipped: jsonschema is not installed")
        return None
    conn = http.client.HTTPConnection("localhost", port, timeout=20)
    try:
        conn.request("GET", "/openapi.json")
        resp = conn.getresponse()
        body = resp.read().decode("utf-8", "replace")
        if resp.status != 200:
            if REQUIRED:
                raise SystemExit(f"REQUIRE_OPENAPI_CONFORMANCE=1 but GET /openapi.json returned {resp.status}")
            return None
        return Conformance(json.loads(body))
    finally:
        conn.close()
