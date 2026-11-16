#!/usr/bin/env python3
"""Checks what a generated GraphQL server answers, field by field, over raw HTTP and WebSocket.

usage: run_graphql.py <server-name> <port> [case-name-filter]

Every server gets the same cases.json, so a difference between servers is a failure on one of them.
A case is a list of steps; a step sends one GraphQL request and compares the response with `expect`:

  data        compared with the response data (see `matches` for the $-operators)
  errors      true: an `errors` array is required; false (default when `data` is given): none allowed
  errorPath   the `path` the first error must carry
  capture     {"name": "dot.path"}: keeps a value of the response data for later steps as {{name}}

A `ws` case opens one graphql-transport-ws socket, subscribes, runs its `trigger` steps over HTTP,
then compares what each subscription received. Cases a server is known to fail are in
known_defects.json; a known defect that passes is a failure too, so the entry gets removed.
"""
import http.client
import json
import os
import re
import socket
import sys
import time
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "server_faults"))
from run_faults import LEAK, Ws, WsClosed  # noqa: E402

TIMEOUT = 15


def substitute(value, captured):
    if isinstance(value, dict):
        return {k: substitute(v, captured) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, captured) for v in value]
    if isinstance(value, str):
        whole = re.fullmatch(r"\{\{(\w+)\}\}", value)
        if whole:
            return captured[whole.group(1)]
        return re.sub(r"\{\{(\w+)\}\}", lambda m: str(captured[m.group(1)]), value)
    return value


def squash(text):
    return re.sub(r"\s+", "", text)


def matches(expected, actual, path="data"):
    """Returns the first difference, or None.

    $set: same elements in any order. $contains: these elements are present.
    $absent: none of these elements are present. $len: list length.
    $squash: string equal once whitespace is removed. $oneOf: matches one of the alternatives. $all: matches every one.
    $any: anything, null included.
    """
    if isinstance(expected, dict) and len(expected) == 1 and next(iter(expected)).startswith("$"):
        op, arg = next(iter(expected.items()))
        if op == "$any":
            return None
        if op == "$all":
            return next((d for d in (matches(m, actual, path) for m in arg) if d), None)
        if op == "$oneOf":
            return None if any(matches(alt, actual, path) is None for alt in arg) else f"{path}: {actual!r} is none of {arg!r}"
        if op == "$squash":
            return None if isinstance(actual, str) and squash(actual) == squash(arg) else f"{path}: {actual!r} != {arg!r}"
        if not isinstance(actual, list):
            return f"{path}: expected a list, got {actual!r}"
        if op == "$len":
            return None if len(actual) == arg else f"{path}: length {len(actual)} != {arg}"
        if op == "$set":
            rest = list(actual)
            for item in arg:
                hit = next((i for i, a in enumerate(rest) if matches(item, a) is None), None)
                if hit is None:
                    return f"{path}: missing {item!r} in {actual!r}"
                rest.pop(hit)
            return f"{path}: unexpected {rest!r}" if rest else None
        if op == "$contains":
            for item in arg:
                if not any(matches(item, a) is None for a in actual):
                    return f"{path}: missing {item!r} in {actual!r}"
            return None
        if op == "$absent":
            for item in arg:
                if any(matches(item, a) is None for a in actual):
                    return f"{path}: unexpected {item!r} in {actual!r}"
            return None
        raise ValueError(f"unknown operator {op}")
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return f"{path}: expected an object, got {actual!r}"
        for k, v in expected.items():
            if k not in actual:
                return f"{path}.{k}: missing"
            diff = matches(v, actual[k], f"{path}.{k}")
            if diff:
                return diff
        extra = set(actual) - set(expected)
        return f"{path}: unexpected fields {sorted(extra)}" if extra else None
    if isinstance(expected, list):
        if not isinstance(actual, list):
            return f"{path}: expected a list, got {actual!r}"
        if len(expected) != len(actual):
            return f"{path}: length {len(actual)} != {len(expected)}: {actual!r}"
        for i, (e, a) in enumerate(zip(expected, actual)):
            diff = matches(e, a, f"{path}[{i}]")
            if diff:
                return diff
        return None
    if isinstance(expected, bool) or isinstance(actual, bool):
        return None if expected is actual else f"{path}: {actual!r} != {expected!r}"
    return None if expected == actual else f"{path}: {actual!r} != {expected!r}"


def dig(doc, dotted):
    for part in dotted.split("."):
        doc = doc[int(part)] if isinstance(doc, list) else doc[part]
    return doc


def post(port, payload, method="POST"):
    conn = http.client.HTTPConnection("localhost", port, timeout=TIMEOUT)
    try:
        if method == "GET":
            qs = "&".join(f"{k}={quote(v if isinstance(v, str) else json.dumps(v))}" for k, v in payload.items())
            conn.request("GET", "/graphql?" + qs, headers={"Accept": "application/json"})
        else:
            conn.request("POST", "/graphql", body=json.dumps(payload).encode(),
                         headers={"Content-Type": "application/json", "Accept": "application/json"})
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8", "replace")
    finally:
        conn.close()


def payload_of(step, captured):
    payload = {"query": substitute(step["query"], captured)}
    if "variables" in step:
        payload["variables"] = substitute(step["variables"], captured)
    if "operationName" in step:
        payload["operationName"] = step["operationName"]
    return payload


def check_response(step, doc, captured, label):
    expect = substitute(step.get("expect", {}), captured)
    problems = []
    errors = doc.get("errors") if isinstance(doc, dict) else None
    wants_errors = expect.get("errors", False if "data" in expect else None)
    if wants_errors is True and not errors:
        problems.append(f"{label}: expected errors, got {json.dumps(doc)[:200]}")
    if wants_errors is False and errors:
        problems.append(f"{label}: unexpected errors {json.dumps(errors)[:300]}")
    if "errorPath" in expect and errors:
        if errors[0].get("path") != expect["errorPath"]:
            problems.append(f"{label}: error path {errors[0].get('path')!r} != {expect['errorPath']!r}")
    if "data" in expect:
        diff = matches(expect["data"], doc.get("data") if isinstance(doc, dict) else None)
        if diff:
            problems.append(f"{label}: {diff}")
    for name, dotted in step.get("capture", {}).items():
        try:
            captured[name] = dig(doc["data"], dotted)
        except (KeyError, IndexError, TypeError):
            problems.append(f"{label}: cannot capture {dotted}")
    return problems


def run_steps(steps, port, captured):
    problems = []
    for i, step in enumerate(steps):
        label = f"step {i + 1}"
        try:
            status, text = post(port, payload_of(step, captured), step.get("method", "POST"))
        except Exception as e:
            return problems + [f"{label}: no response: {type(e).__name__}: {e}"]
        if LEAK.search(text):
            problems.append(f"{label}: response leaks internals: {LEAK.search(text).group(0)!r}")
        allowed = step.get("status", [200])
        if status not in allowed:
            problems.append(f"{label}: status {status}, expected {allowed}: {text[:200]}")
            continue
        if status in step.get("statusOnly", [405]) and status in allowed:
            continue
        try:
            doc = json.loads(text)
        except ValueError:
            problems.append(f"{label}: not JSON: {text[:200]!r}")
            continue
        problems += check_response(step, doc, captured, label)
    return problems


def run_http_case(case, port):
    return run_steps(case.get("steps") or [case], port, {})


def ws_receive(ws, until):
    ws.sock.settimeout(max(0.05, until - time.time()))
    try:
        return json.loads(ws.recv())
    except socket.timeout:
        return None


def run_ws_case(case, port):
    captured = {}
    problems = run_steps(case.get("setup", []), port, captured)
    if problems:
        return problems
    try:
        ws = Ws(port)
    except Exception as e:
        return [f"handshake failed: {e}"]
    received = {sub["id"]: [] for sub in case["subscribe"]}
    completed = set()
    errors = {}
    try:
        ws.send(json.dumps({"type": "connection_init"}))
        ack = ws_receive(ws, time.time() + TIMEOUT)
        if not ack or ack.get("type") != "connection_ack":
            return [f"no connection_ack: {ack!r}"]
        for sub in case["subscribe"]:
            ws.send(json.dumps({"id": sub["id"], "type": "subscribe", "payload": payload_of(sub, captured)}))
        time.sleep(case.get("settle", 0.7))
        for sub_id in case.get("stopBeforeTrigger", []):
            ws.send(json.dumps({"id": sub_id, "type": "complete"}))
        time.sleep(0.2)
        problems += run_steps(case.get("trigger", []), port, captured)

        expect = substitute(case["expect"], captured)

        def satisfied():
            for sub_id, exp in expect.items():
                if exp.get("complete") and sub_id not in completed and sub_id not in errors:
                    return False
                if exp.get("error") and sub_id not in errors:
                    return False
                if len(received[sub_id]) < len(exp.get("next", [])) and sub_id not in completed and sub_id not in errors:
                    return False
            return True

        deadline = time.time() + case.get("timeout", 10)
        quiet_until = None
        while time.time() < deadline:
            if satisfied():
                quiet_until = quiet_until or time.time() + case.get("quiet", 1.0)
                if time.time() >= quiet_until:
                    break
            msg = ws_receive(ws, quiet_until or deadline)
            if msg is None:
                continue
            sub_id, kind = msg.get("id"), msg.get("type")
            if kind == "next" and sub_id in received:
                received[sub_id].append(msg.get("payload", {}))
            elif kind == "complete":
                completed.add(sub_id)
            elif kind == "error":
                errors[sub_id] = msg.get("payload")
            elif kind == "ping":
                ws.send(json.dumps({"type": "pong"}))
    except WsClosed as c:
        problems.append(f"socket closed with {c.code}")
    except Exception as e:
        problems.append(f"{type(e).__name__}: {e}")
    finally:
        ws.close()

    for sub_id, exp in expect.items():
        got = received[sub_id]
        if LEAK.search(json.dumps(got) + json.dumps(errors.get(sub_id))):
            problems.append(f"{sub_id}: leaks internals")
        if exp.get("error"):
            if sub_id not in errors and not any(p.get("errors") for p in got):
                problems.append(f"{sub_id}: expected an error, got {json.dumps(got)[:200]}")
            continue
        if sub_id in errors:
            problems.append(f"{sub_id}: error {json.dumps(errors[sub_id])[:200]}")
        payload_errors = [p["errors"] for p in got if p.get("errors")]
        if payload_errors:
            problems.append(f"{sub_id}: errors in next {json.dumps(payload_errors)[:200]}")
        wanted = exp.get("next", [])
        exact = exp.get("exact", True)
        datas = [p.get("data") for p in got]
        if exact and len(datas) != len(wanted):
            problems.append(f"{sub_id}: {len(datas)} events, expected {len(wanted)}: {json.dumps(datas)[:300]}")
        for i, want in enumerate(wanted):
            if i >= len(datas):
                problems.append(f"{sub_id}: event {i + 1} missing")
                break
            diff = matches(want, datas[i], f"{sub_id}[{i}]")
            if diff:
                problems.append(diff)
        if exp.get("complete") and sub_id not in completed:
            problems.append(f"{sub_id}: no complete message")
        if exp.get("complete") is False and sub_id in completed:
            problems.append(f"{sub_id}: completed unexpectedly")
    return problems


def main():
    server, port = sys.argv[1], int(sys.argv[2])
    only = sys.argv[3] if len(sys.argv) > 3 else None
    cases = json.load(open(os.path.join(HERE, "cases.json")))
    known = json.load(open(os.path.join(HERE, "known_defects.json"))).get(server, {})
    runs = [(c["name"], c, run_http_case) for c in cases["http"]]
    runs += [(c["name"], c, run_ws_case) for c in cases["ws"]]
    if only:
        runs = [r for r in runs if only in r[0]]

    names = [r[0] for r in runs]
    duplicates = {n for n in names if names.count(n) > 1}
    if duplicates:
        sys.exit(f"duplicate case names: {sorted(duplicates)}")

    failed, stale, expected = [], [], 0
    for name, case, fn in runs:
        problems = fn(case, port)
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

    print(f"\n{server}: {len(runs) - len(failed) - len(stale) - expected} ok, "
          f"{expected} known defects, {len(failed)} failed, {len(stale)} stale")
    sys.exit(1 if failed or stale else 0)


if __name__ == "__main__":
    main()
