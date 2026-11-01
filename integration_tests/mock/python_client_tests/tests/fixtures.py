import json
from typing import Any, Dict, List

ADDRESS: Dict[str, Any] = {"street": "123 Main St", "city": "Springfield", "country": "US", "zip": "12345"}
ADDRESS_NO_ZIP: Dict[str, Any] = {"street": "456 Oak Ave", "city": "Shelbyville", "country": "US", "zip": None}
BILLING_ADDRESS: Dict[str, Any] = {"street": "789 Pine Rd", "city": "Capital City", "country": "US", "zip": "99999"}

USER_ALICE: Dict[str, Any] = {
    "id": "user-1",
    "name": "Alice Smith",
    "email": "alice@test.com",
    "status": "ACTIVE",
    "priority": "HIGH",
    "address": ADDRESS,
    "billingAddress": None,
    "tags": ["admin", "beta"],
    "scores": [10, 20, 30],
}

USER_BOB: Dict[str, Any] = {
    "id": "user-2",
    "name": "Bob Jones",
    "email": "bob@test.com",
    "status": "INACTIVE",
    "priority": None,
    "address": ADDRESS_NO_ZIP,
    "billingAddress": BILLING_ADDRESS,
    "tags": [],
    "scores": None,
}

ALL_SCALARS_NULL: Dict[str, Any] = {
    "id": "scalar-1",
    "strVal": "hello world",
    "intVal": 42,
    "floatVal": 3.14,
    "boolVal": True,
    "nullableStr": None,
    "nullableInt": None,
    "nullableFloat": None,
    "nullableBool": None,
    "nullableId": None,
}

ALL_SCALARS_PRESENT: Dict[str, Any] = {
    "id": "scalar-2",
    "strVal": "edge case",
    "intVal": -1,
    "floatVal": -0.5,
    "boolVal": False,
    "nullableStr": "present",
    "nullableInt": 99,
    "nullableFloat": 2.718,
    "nullableBool": False,
    "nullableId": "nid-1",
}

POST: Dict[str, Any] = {
    "id": "post-1",
    "title": "Hello World",
    "body": "Post body text.",
    "author": USER_ALICE,
    "coAuthor": None,
    "viewCount": 128,
}

POST_WITH_CO_AUTHOR: Dict[str, Any] = {
    "id": "post-2",
    "title": "Collaboration",
    "body": "Written together.",
    "author": USER_ALICE,
    "coAuthor": USER_BOB,
    "viewCount": 42,
}

AUDIT_ENTRY: Dict[str, Any] = {"id": "audit-1", "action": "LOGIN", "performedBy": "user-1"}

AUDIT_ENTRY_WITH_EXTRA: Dict[str, Any] = {
    "id": "audit-2",
    "action": "LOGOUT",
    "performedBy": "user-1",
    "internalNote": "this should be silently ignored",
}

POST_WITH_AUTHOR_CYCLE: Dict[str, Any] = {
    "id": "post-10",
    "title": "Cyclic Post",
    "body": "Body text.",
    "author": {
        "id": "user-1",
        "name": "Alice Smith",
        "email": "alice@test.com",
        "status": "ACTIVE",
        "priority": "HIGH",
        "address": ADDRESS,
        "billingAddress": None,
        "tags": ["admin"],
        "scores": None,
        "posts": None,
    },
    "coAuthor": None,
    "viewCount": 7,
}

USER_WITH_POSTS: Dict[str, Any] = {
    "id": "user-1",
    "name": "Alice Smith",
    "email": "alice@test.com",
    "status": "ACTIVE",
    "priority": "HIGH",
    "address": ADDRESS,
    "billingAddress": None,
    "tags": ["admin", "beta"],
    "scores": [10, 20, 30],
    "posts": [POST_WITH_AUTHOR_CYCLE],
}

TAGS: List[Dict[str, Any]] = [
    {"id": "tag-1", "label": "dart", "color": "#0175C2"},
    {"id": "tag-2", "label": "graphql", "color": None},
]

GRAPHQL_ERROR: Dict[str, Any] = {
    "message": "Not found",
    "locations": [{"line": 1, "column": 1}],
    "path": ["getUser"],
}


def data_response(data: Dict[str, Any]) -> str:
    return json.dumps({"data": data})


def error_response(errors: List[Dict[str, Any]]) -> str:
    return json.dumps({"data": None, "errors": errors})
