#!/usr/bin/env python3
"""Checks the OpenAPI document and the Swagger UI page a generated server serves for its REST operations.

usage: run_openapi.py <server-name> <port> [graphql-only]

Swagger UI draws its endpoint list in the browser, so there is nothing to scrape from the HTML itself. The page is parsed
instead for what the browser needs: the pinned Swagger UI script and stylesheet, the mount element, and the spec URL its
inline script loads. That URL is then fetched, and the document behind it is validated with openapi-spec-validator (when installed) and checked against the REST operations of
schema_rest/rest.gql: every operation the REST suite lists present, no invented ones, references resolving, path parameters declared, operation ids unique.
With `graphql-only` nothing may be served.
"""
import ast
import http.client
import json
import os
import re
import sys
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
TIMEOUT = 20
SWAGGER_BUNDLE = re.compile(r"swagger-ui-dist@\d+\.\d+\.\d+/swagger-ui-bundle\.js$")
SWAGGER_CSS = re.compile(r"swagger-ui-dist@\d+\.\d+\.\d+/swagger-ui\.css$")
SPEC_URL = re.compile(r"url:\s*'((?:[^'\\]|\\.)*)'")
METHODS = {"get", "put", "post", "delete", "patch", "head", "options", "trace"}


class SwaggerPage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.scripts = []
        self.inline_scripts = []
        self.stylesheets = []
        self.mount_ids = []
        self._in_title = False
        self._in_inline_script = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self._in_title = True
        elif tag == "script":
            if attrs.get("src"):
                self.scripts.append(attrs["src"])
            else:
                self._in_inline_script = True
                self.inline_scripts.append("")
        elif tag == "link" and attrs.get("rel") == "stylesheet":
            self.stylesheets.append(attrs.get("href", ""))
        elif tag == "div" and attrs.get("id"):
            self.mount_ids.append(attrs["id"])

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        elif tag == "script":
            self._in_inline_script = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif self._in_inline_script:
            self.inline_scripts[-1] += data


def get(port, path):
    conn = http.client.HTTPConnection("localhost", port, timeout=TIMEOUT)
    try:
        conn.request("GET", path)
        resp = conn.getresponse()
        return resp.status, resp.getheader("Content-Type") or "", resp.read().decode("utf-8", "replace")
    finally:
        conn.close()


def rest_operations():
    tree = ast.parse(open(os.path.join(HERE, "..", "server_rest", "run_rest.py"), encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "REST_OPERATIONS" for t in node.targets):
            return set(ast.literal_eval(node.value))
    raise RuntimeError("REST_OPERATIONS not found in server_rest/run_rest.py")


def refs(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "$ref" and isinstance(value, str):
                yield value
            else:
                yield from refs(value)
    elif isinstance(node, list):
        for item in node:
            yield from refs(item)


def resolve(spec, ref):
    if not ref.startswith("#/"):
        return None
    node = spec
    for part in ref[2:].split("/"):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def check_page(port, failures):
    status, content_type, body = get(port, "/docs")
    if status != 200:
        failures.append(f"GET /docs returned {status}")
        return None
    if "text/html" not in content_type:
        failures.append(f"/docs content type is {content_type!r}, not text/html")
    page = SwaggerPage()
    page.feed(body)
    if not page.title.strip():
        failures.append("/docs has no <title>")
    if not any(SWAGGER_BUNDLE.search(src) for src in page.scripts):
        failures.append(f"/docs does not load a pinned swagger-ui-bundle.js: {page.scripts}")
    if not any(SWAGGER_CSS.search(href) for href in page.stylesheets):
        failures.append(f"/docs does not load a pinned swagger-ui.css: {page.stylesheets}")
    if "swagger-ui" not in page.mount_ids:
        failures.append(f"/docs has no #swagger-ui mount element: {page.mount_ids}")
    urls = [m.group(1) for script in page.inline_scripts for m in SPEC_URL.finditer(script)]
    if len(urls) != 1:
        failures.append(f"/docs inline script should name exactly one spec url, found {urls}")
        return None
    return urls[0].replace("\\'", "'").replace("\\/", "/")


def check_spec(port, spec_path, failures):
    status, content_type, body = get(port, spec_path)
    if status != 200:
        failures.append(f"GET {spec_path} returned {status}")
        return
    if "application/json" not in content_type:
        failures.append(f"{spec_path} content type is {content_type!r}")
    try:
        spec = json.loads(body)
    except ValueError as error:
        failures.append(f"{spec_path} is not JSON: {error}")
        return
    check_valid(spec, failures)
    if not str(spec.get("openapi", "")).startswith("3.1"):
        failures.append(f"openapi version is {spec.get('openapi')!r}, expected 3.1.x")
    if spec.get("servers") != [{"url": "/"}]:
        failures.append(f"servers is {spec.get('servers')!r}")

    operations = {}
    for path, item in spec.get("paths", {}).items():
        for method, op in item.items():
            if method not in METHODS:
                continue
            op_id = op.get("operationId")
            if op_id in operations:
                failures.append(f"operationId {op_id} is used twice")
            operations[op_id] = (method, path, op)
    expected = rest_operations()
    missing = sorted(expected - set(operations))
    schema = open(os.path.join(HERE, "..", "schema_rest", "rest.gql"), encoding="utf-8").read()
    unknown = sorted(op for op in operations if not re.search(rf"\b{re.escape(str(op))}\b", schema))
    if missing:
        failures.append(f"operations missing from the spec: {missing}")
    if unknown:
        failures.append(f"operations in the spec that rest.gql does not declare: {unknown}")

    for op_id, (method, path, op) in operations.items():
        placeholders = set(re.findall(r"\{([^{}]+)\}", path))
        declared = {p["name"] for p in op.get("parameters", []) if p.get("in") == "path"}
        if placeholders != declared:
            failures.append(f"{op_id}: path {path} has placeholders {sorted(placeholders)}, parameters {sorted(declared)}")
        if not any(code.startswith(("2", "default")) for code in op.get("responses", {})):
            failures.append(f"{op_id}: no success response")
        if method in ("get", "head") and "requestBody" in op:
            failures.append(f"{op_id}: {method} carries a request body")

    for ref in set(refs(spec)):
        if resolve(spec, ref) is None:
            failures.append(f"dangling reference {ref}")
    print(f"{len(operations)} operations, {len(spec.get('components', {}).get('schemas', {}))} schemas")


def check_valid(spec, failures):
    try:
        from openapi_spec_validator import validate
    except ImportError:
        if os.environ.get("REQUIRE_OPENAPI_CONFORMANCE") == "1":
            failures.append("REQUIRE_OPENAPI_CONFORMANCE=1 but openapi-spec-validator is not installed")
        else:
            print("spec validation skipped: openapi-spec-validator is not installed")
        return
    try:
        validate(spec)
    except Exception as error:
        failures.append(f"the spec is not a valid OpenAPI document: {str(error)[:300]}")


def check_absent(port, failures):
    for path in ("/openapi.json", "/docs"):
        status, _, _ = get(port, path)
        if status == 200:
            failures.append(f"GET {path} returned 200 on a server without REST operations")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    server, port = sys.argv[1], int(sys.argv[2])
    graphql_only = len(sys.argv) > 3 and sys.argv[3] == "graphql-only"
    failures = []
    if graphql_only:
        check_absent(port, failures)
    else:
        spec_path = check_page(port, failures)
        check_spec(port, spec_path or "/openapi.json", failures)
    for failure in failures:
        print(f"FAIL {server}: {failure}")
    if failures:
        sys.exit(1)
    print(f"{server}: OpenAPI checks passed")


if __name__ == "__main__":
    main()
