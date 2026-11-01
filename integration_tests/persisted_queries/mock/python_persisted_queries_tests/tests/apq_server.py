import hashlib
import json
from typing import Any, Dict, List, Optional, Set

from generated import GraphLinkGetNotSupported, GraphLinkWebSocketAdapter


class NoWebSocketAdapter(GraphLinkWebSocketAdapter):
    async def connect(self) -> None:
        return None

    async def send_message(self, message: str) -> None:
        return None

    async def close(self) -> None:
        return None


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class ApqServer:
    """Apollo-style APQ server in front of canned responses."""

    def __init__(self) -> None:
        self._responses: Dict[str, Dict[str, Any]] = {}
        self._registered: Set[str] = set()
        self.requests: List[Dict[str, Any]] = []
        self.methods: List[str] = []
        self.supported = True
        self.not_found_message = "PersistedQueryNotFound"
        self.get_supported = True
        self.fail_with: Optional[Exception] = None
        self.get_fail_with: Optional[Exception] = None

    def respond_to(self, operation_name: str, data: Dict[str, Any]) -> None:
        self._responses[operation_name] = {"data": data}

    def respond_with_errors(self, operation_name: str, errors: List[Dict[str, Any]]) -> None:
        self._responses[operation_name] = {"data": None, "errors": errors}

    def evict(self) -> None:
        self._registered.clear()

    @staticmethod
    def is_hash_only(body: Dict[str, Any]) -> bool:
        return "extensions" in body and "query" not in body

    async def call(self, payload: str) -> str:
        self.methods.append("POST")
        return self.handle(payload, self.fail_with)

    async def get(self, payload: str) -> str:
        self.methods.append("GET")
        if not self.get_supported:
            raise GraphLinkGetNotSupported("GET is not allowed")
        return self.handle(payload, self.get_fail_with)

    def handle(self, payload: str, failure: Optional[Exception]) -> str:
        body = json.loads(payload)
        self.requests.append(body)
        if failure is not None:
            raise failure
        persisted = (body.get("extensions") or {}).get("persistedQuery")
        if persisted is not None:
            if not self.supported:
                return self._error("PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED")
            digest = persisted["sha256Hash"]
            query = body.get("query")
            if query is None:
                if digest not in self._registered:
                    return self._error(self.not_found_message, "PERSISTED_QUERY_NOT_FOUND")
            else:
                if sha256_hex(query) != digest:
                    return self._error("provided sha does not match query", "INTERNAL_SERVER_ERROR")
                self._registered.add(digest)
        response = self._responses.get(body["operationName"])
        if response is None:
            raise RuntimeError(f"No response registered for {body['operationName']}")
        return json.dumps(response)

    @staticmethod
    def _error(message: str, code: str) -> str:
        return json.dumps({"errors": [{"message": message, "extensions": {"code": code}}]})
