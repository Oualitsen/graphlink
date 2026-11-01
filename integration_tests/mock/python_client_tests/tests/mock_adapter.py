import asyncio
import json
import re
from typing import Any, Dict, List, Optional

from generated import GraphLinkWebSocketAdapter

_OPERATION_NAME = re.compile(r"(?:query|mutation|subscription)\s+(\w+)")


def parse_operation_name(query: str) -> Optional[str]:
    match = _OPERATION_NAME.match(query.strip())
    return match.group(1) if match else None


class GraphLinkCall:
    def __init__(self, operation_name: Optional[str], variables: Dict[str, Any], raw_payload: str) -> None:
        self.operation_name = operation_name
        self.variables = variables
        self.raw_payload = raw_payload


class MockAdapter:
    def __init__(self) -> None:
        self._responses: Dict[str, str] = {}
        self.calls: List[GraphLinkCall] = []
        self.simulate_failure = False

    def register(self, operation_name: str, json_response: str) -> None:
        self._responses[operation_name] = json_response

    def register_data(self, operation_name: str, data: Dict[str, Any]) -> None:
        self.register(operation_name, json.dumps({"data": data}))

    def register_errors(self, operation_name: str, errors: List[Dict[str, Any]]) -> None:
        self.register(operation_name, json.dumps({"data": None, "errors": errors}))

    @property
    def last_call(self) -> Optional[GraphLinkCall]:
        return self.calls[-1] if self.calls else None

    @property
    def call_count(self) -> int:
        return len(self.calls)

    def reset(self) -> None:
        self.calls.clear()
        self._responses.clear()
        self.simulate_failure = False

    async def call(self, payload: str) -> str:
        if self.simulate_failure:
            raise Exception("Simulated network failure")
        decoded = json.loads(payload)
        query = decoded.get("query") or ""
        variables = decoded.get("variables") or {}
        operation_name = parse_operation_name(query)
        self.calls.append(GraphLinkCall(operation_name, variables, payload))
        if operation_name is not None and operation_name in self._responses:
            return self._responses[operation_name]
        raise RuntimeError(
            f'MockAdapter: no response registered for "{operation_name or "unknown"}".\n'
            f"Registered operations: {list(self._responses)}\nPayload: {payload}"
        )


class MockMultipartAdapter:
    def __init__(self) -> None:
        self._responses: Dict[str, str] = {}
        self.calls: List[Dict[str, Any]] = []

    def register_data(self, operation_name: str, data: Dict[str, Any]) -> None:
        self._responses[operation_name] = json.dumps({"data": data})

    @property
    def last_call(self) -> Optional[Dict[str, Any]]:
        return self.calls[-1] if self.calls else None

    @property
    def call_count(self) -> int:
        return len(self.calls)

    async def call(self, parts: Dict[str, Any], on_progress: Any = None) -> str:
        self.calls.append(dict(parts))
        decoded = json.loads(parts["operations"])
        operation_name = parse_operation_name(decoded.get("query") or "")
        if operation_name is not None and operation_name in self._responses:
            return self._responses[operation_name]
        raise RuntimeError(f'MockMultipartAdapter: no response registered for "{operation_name or "unknown"}".')


class MockWebSocketAdapter(GraphLinkWebSocketAdapter):
    def __init__(self) -> None:
        super().__init__()
        self.sent_messages: List[Dict[str, Any]] = []
        self._subscription_id: Optional[str] = None
        self._ready = asyncio.Event()

    async def subscription_ready(self) -> None:
        await self._ready.wait()

    def push_event(self, data: Dict[str, Any]) -> None:
        self.on_message(json.dumps({"id": self._subscription_id, "type": "next", "payload": {"data": data}}))

    def push_complete(self) -> None:
        self.on_message(json.dumps({"id": self._subscription_id, "type": "complete"}))

    def push(self, message: str) -> None:
        self.on_message(message)

    def reconnect(self) -> None:
        self.on_reconnect()

    async def connect(self) -> None:
        return None

    async def send_message(self, message: str) -> None:
        decoded = json.loads(message)
        self.sent_messages.append(decoded)
        message_type = decoded.get("type")
        if message_type == "connection_init":
            asyncio.get_running_loop().call_soon(lambda: self.on_message(json.dumps({"type": "connection_ack"})))
        elif message_type == "subscribe":
            self._subscription_id = decoded.get("id")
            self._ready.set()

    async def close(self) -> None:
        return None
