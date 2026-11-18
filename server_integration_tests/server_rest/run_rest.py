#!/usr/bin/env python3
"""Exercises the REST operations of a generated server over raw HTTP.

usage: run_rest.py <server-name> <port>

Every server serves the same schema_rest/rest.gql, so one table of cases (cases.json) drives all of them. A case
passes when the status is allowed, the body matches (a missing JSON key equals a null one), nothing internal leaks, an
error body is empty or JSON, and the server still answers afterwards. Cases a server is known to fail are in
known_defects.json; a known defect that passes is itself a failure, so entries get removed.
"""
import http.client
import json
import os
import re
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
TIMEOUT = 20
LEAK = re.compile(
    r"\bat [\w$.<>]+\([\w$.]+\.(java|kt|ts|js|mjs):\d+\)"
    r"|node_modules|org\.springframework|java\.lang\.|kotlinx?\.|graphql\.GraphQLException"
    r"|/Users/|/home/runner|\.java:\d+|\.kt:\d+|\.ts:\d+|boom \d+|invalid name"
)
REST_OPERATIONS = {
    "restItem", "restScalars", "restItemByColor", "restSearch", "restTags", "restGreeting", "restPlain", "restCount",
    "restFlag", "restColors", "restHeaders", "restFail", "restCreate", "restReplace", "restPatch", "restDelete",
    "restBulk", "restOptionalBody", "restValidated", "restKeywords", "restUpload", "restUploadMany", "restUploadOptional", "restUploadRaw",
    "restForm", "restFormUpdate", "restFormOptional", "restIntercepted", "restInjected", "restUnguarded", "restBlockGuarded",
    "restInterceptedBody", "restInterceptedVoid", "restDownload", "restDownloadOptional", "restDownloadLarge",
}


def expand(value):
    if isinstance(value, dict):
        return {k: expand(v) for k, v in value.items()}
    if isinstance(value, list):
        return [expand(v) for v in value]
    if isinstance(value, str):
        value = re.sub(r"\{\{repeat:(.):(\d+)\}\}", lambda m: m.group(1) * int(m.group(2)), value)
        value = re.sub(r"\{\{nested:(\d+)\}\}", lambda m: "[" * int(m.group(1)) + "]" * int(m.group(1)), value)
    return value


def request_full(port, method, path, body=None, headers=None, chunked=False):
    conn = http.client.HTTPConnection("localhost", port, timeout=TIMEOUT)
    try:
        conn.request(method, path, body=body, headers=headers or {}, encode_chunked=chunked)
        resp = conn.getresponse()
        raw = resp.read()
        return resp.status, resp.getheader("Content-Type") or "", raw, {k.lower(): v for k, v in resp.getheaders()}
    finally:
        conn.close()


def request(port, method, path, body=None, headers=None, chunked=False):
    status, content_type, raw, _ = request_full(port, method, path, body, headers, chunked)
    return status, content_type, raw.decode("utf-8", "replace")


def same(actual, expected):
    if isinstance(expected, bool) or isinstance(actual, bool):
        return isinstance(expected, bool) and isinstance(actual, bool) and expected == actual
    if isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        return float(expected) == float(actual)
    if isinstance(expected, dict) and isinstance(actual, dict):
        keys = {k for k, v in expected.items() if v is not None} | {k for k, v in actual.items() if v is not None}
        return all(same(actual.get(k), expected.get(k)) for k in keys)
    if isinstance(expected, list) and isinstance(actual, list):
        return len(expected) == len(actual) and all(same(a, e) for a, e in zip(actual, expected))
    return actual == expected


def make_bytes(spec):
    size = spec["size"]
    unit = bytes(range(256)) if spec.get("pattern", "range") == "range" else spec["pattern"].encode()
    return (unit * (size // len(unit) + 1))[:size]


def multipart_body(parts, boundary="----glrest0boundary"):
    chunks, sent = [], {}
    for part in parts:
        head = f'--{boundary}\r\nContent-Disposition: form-data; name="{part["name"]}"'
        if "bytes" in part:
            data = make_bytes(part["bytes"])
            sent[part.get("key", part["name"])] = data
            head += f'; filename="{part.get("filename", "file.bin")}"\r\nContent-Type: {part.get("contentType", "application/octet-stream")}'
        else:
            data = part["value"].encode()
        chunks.append(head.encode() + b"\r\n\r\n" + data + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}", sent


def resolve_sent(value, sent):
    import hashlib
    if isinstance(value, dict):
        return {k: resolve_sent(v, sent) for k, v in value.items()}
    if isinstance(value, list):
        return [resolve_sent(v, sent) for v in value]
    if isinstance(value, str):
        m = re.fullmatch(r"\{\{(sha256|size):(\w+)(?::(\d+))?\}\}", value)
        if m:
            data = sent[m.group(2)] if m.group(3) is None else sent[m.group(2)][int(m.group(3))]
            return hashlib.sha256(data).hexdigest() if m.group(1) == "sha256" else len(data)
    return value


def build_request(case):
    method = case.get("method", "GET")
    headers = dict(case.get("headers", {}))
    body = None
    sent = {}
    if "multipart" in case:
        body, headers["Content-Type"], sent = multipart_body(case["multipart"])
        return method, expand(case["path"]), body, headers, sent
    if "raw" in case:
        data = make_bytes(case["raw"])
        sent["raw"] = data
        headers["Content-Type"] = case.get("contentType", "application/octet-stream")
        return method, expand(case["path"]), data if not case.get("chunked") else iter([data[i:i + 65536] for i in range(0, len(data), 65536)]), headers, sent
    if "rawBody" in case:
        body = expand(case["rawBody"]).encode()
    elif "body" in case:
        body = json.dumps(case["body"], ensure_ascii=False).encode()
    elif "bodyTemplate" in case:
        body = json.dumps(expand(case["bodyTemplate"]), ensure_ascii=False).encode()
    if body is not None:
        headers["Content-Type"] = case.get("contentType", "application/json")
    return method, expand(case["path"]), body, headers, sent


CONFORMANCE = None


def load_conformance(port):
    import importlib.util
    path = os.path.join(HERE, "..", "server_openapi", "conformance.py")
    spec = importlib.util.spec_from_file_location("openapi_conformance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.load(port)


def run_case(case, port):
    if "graphql" in case:
        return run_graphql_case(case, port)
    if case.get("graphqlSchemaHasNoRestOperations"):
        return check_schema(port)
    method, path, body, headers, sent = build_request(case)
    try:
        status, content_type, raw, response_headers = request_full(port, method, path, body, headers, chunked=bool(case.get("chunked")))
    except Exception as e:
        return [f"no response: {type(e).__name__}: {e}"]
    text = raw.decode("utf-8", "replace")
    problems = check_response(resolve_case(case, sent), status, content_type, text)
    if CONFORMANCE is not None and not problems:
        problems += CONFORMANCE.check(method, path, status, content_type, text)
    if status < 400:
        problems += check_download(case, raw, response_headers)
    return problems


def pattern_bytes(size, modulus):
    return bytes(i % modulus for i in range(size))


def check_download(case, raw, headers):
    problems = []
    expected = case.get("bytes")
    if expected is not None:
        want = pattern_bytes(expected["size"], expected["mod"])
        if raw != want:
            problems.append(f"download body is {len(raw)} bytes (first {raw[:8].hex()}), expected {len(want)} bytes of i % {expected['mod']}")
    for name, expectation in case.get("responseHeaders", {}).items():
        actual = headers.get(name.lower())
        if expectation is None:
            if actual is not None:
                problems.append(f"header {name} is {actual!r}, expected none")
        elif actual is None:
            problems.append(f"header {name} is missing")
        elif expectation.startswith("contains:"):
            if expectation[len("contains:"):].lower() not in actual.lower():
                problems.append(f"header {name} is {actual!r}, expected it to contain {expectation[len('contains:'):]!r}")
        elif expectation.startswith("prefix:"):
            if not actual.lower().startswith(expectation[len("prefix:"):].lower()):
                problems.append(f"header {name} is {actual!r}, expected it to start with {expectation[len('prefix:'):]!r}")
        elif actual != expectation:
            problems.append(f"header {name} is {actual!r}, expected {expectation!r}")
    return problems


def resolve_case(case, sent):
    if not sent:
        return case
    return {k: resolve_sent(v, sent) if k in ("json", "jsonSubset") else v for k, v in case.items()}


def check_response(case, status, content_type, text):
    problems = []
    allowed = case["status"] if isinstance(case["status"], list) else [case["status"]]
    if status not in allowed:
        problems.append(f"status {status}, expected one of {allowed}: {text[:160]!r}")
    if LEAK.search(text):
        problems.append(f"response leaks internals: {LEAK.search(text).group(0)!r}")
    if status >= 400 and text.strip():
        try:
            json.loads(text)
        except ValueError:
            problems.append(f"error body is not JSON: {text[:160]!r}")
    if "responseType" in case and status < 400 and not content_type.startswith(case["responseType"]):
        problems.append(f"content type {content_type!r}, expected {case['responseType']!r}")
    if case.get("empty") and text.strip() not in ("", "null"):
        problems.append(f"expected an empty body, got {text[:160]!r}")
    if "text" in case and text != expand(case["text"]):
        problems.append(f"body {text[:160]!r}, expected {case['text']!r}")
    if status >= 400:
        return problems
    if "json" in case or "jsonSubset" in case or "jsonSubsetLength" in case:
        try:
            doc = json.loads(text)
        except ValueError:
            return problems + [f"body is not JSON: {text[:160]!r}"]
        if "json" in case and not same(doc, expand(case["json"])):
            problems.append(f"body {json.dumps(doc, ensure_ascii=False)[:300]}, expected {json.dumps(expand(case['json']), ensure_ascii=False)[:300]}")
        for key, expected in case.get("jsonSubset", {}).items():
            if not isinstance(doc, dict) or not same(doc.get(key), expected):
                problems.append(f"{key}: {json.dumps(doc.get(key) if isinstance(doc, dict) else doc, ensure_ascii=False)[:160]}, expected {expected!r}")
        for key, length in case.get("jsonSubsetLength", {}).items():
            if not isinstance(doc, dict) or len(doc.get(key) or "") != length:
                problems.append(f"{key} length differs from {length}")
    return problems


def run_graphql_case(case, port):
    try:
        status, content_type, text = request(port, "POST", "/graphql", json.dumps({"query": case["graphql"]}).encode(),
                                             {"Content-Type": "application/json"})
    except Exception as e:
        return [f"no response: {type(e).__name__}: {e}"]
    return check_response(case, status, content_type, text)


def root_fields(port, root):
    query = "{ __schema { %s { fields { name } } } }" % root
    status, _, text = request(port, "POST", "/graphql", json.dumps({"query": query}).encode(), {"Content-Type": "application/json"})
    return {f["name"] for f in (json.loads(text)["data"]["__schema"][root] or {}).get("fields", [])}


def check_schema(port):
    try:
        names = root_fields(port, "queryType") | root_fields(port, "mutationType")
    except Exception as e:
        return [f"introspection failed: {type(e).__name__}: {e}"]
    problems = []
    exposed = sorted(names & REST_OPERATIONS)
    if exposed:
        problems.append(f"REST operations exposed in the GraphQL schema: {exposed}")
    if "restItemGraphql" not in names:
        problems.append("the GraphQL operation next to the REST ones is missing from the schema")
    return problems


def alive(port):
    try:
        status, _, text = request(port, "GET", "/rest/count")
        return status == 200 and text.strip() == "42"
    except Exception:
        return False


def concurrency(port):
    failures = []

    def worker(i):
        try:
            status, _, text = request(port, "GET", f"/rest/items/c{i}")
            if status != 200 or json.loads(text).get("id") != f"c{i}":
                failures.append(f"c{i}: {status} {text[:80]!r}")
        except Exception as e:
            failures.append(f"c{i}: {type(e).__name__}: {e}")

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(80)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    return failures[:3]


def served(port, method, path, body=None, headers=None):
    try:
        status, _, _ = request(port, method, path, body, headers or {})
    except Exception as e:
        return f"no response: {type(e).__name__}: {e}"
    return status


def check_absent(port, mode):
    if mode == "rest-only":
        status = served(port, "POST", "/graphql", json.dumps({"query": "{ __typename }"}).encode(), {"Content-Type": "application/json"})
        what = "GraphQL endpoint"
    else:
        status = served(port, "GET", "/rest/count")
        what = "REST route"
    if status != 404:
        print(f"FAIL absent_{mode}: the {what} answers {status}, expected 404")
        return 1
    print(f"  ok      absent_{mode}")
    return 0


def main():
    name, port = sys.argv[1], int(sys.argv[2])
    mode = sys.argv[3] if len(sys.argv) > 3 else "mix"
    if mode == "graphql-only":
        sys.exit(check_absent(port, mode))
    global CONFORMANCE
    CONFORMANCE = load_conformance(port)
    cases = json.load(open(os.path.join(HERE, "cases.json")))
    if mode == "rest-only":
        cases = [c for c in cases if "graphql" not in c and not c.get("graphqlSchemaHasNoRestOperations")]
    defects_file = os.path.join(HERE, "known_defects.json")
    known = json.load(open(defects_file)).get(name, {}) if os.path.exists(defects_file) else {}
    failed, passed, known_hit = [], 0, 0
    for case in cases:
        problems = run_case(case, port)
        if not problems and not alive(port):
            problems = ["the server stopped answering after this case"]
        label = case["name"]
        if label in known:
            if problems:
                known_hit += 1
                print(f"KNOWN {label}: {known[label]}")
            else:
                failed.append((label, ["known defect now passes: remove it from known_defects.json"]))
            continue
        if problems:
            failed.append((label, problems))
            print(f"FAIL {label}: {'; '.join(problems)}")
        else:
            passed += 1
    stale = [k for k in known if k not in {c['name'] for c in cases}]
    for label in stale:
        failed.append((label, ["known defect names no case"]))
    problems = concurrency(port)
    if problems:
        failed.append(("concurrency", problems))
        print(f"FAIL concurrency: {problems}")
    if mode == "rest-only" and check_absent(port, mode):
        failed.append(("absent_rest-only", ["the GraphQL endpoint answers"]))
    print(f"{name}: {passed} ok, {known_hit} known defects, {len(failed)} failed of {len(cases) + 1}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
