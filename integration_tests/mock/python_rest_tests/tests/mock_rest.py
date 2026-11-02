import json
from typing import Any, Dict, List, Optional

from generated import (
    GraphLinkClient,
    GLUpload,
    RestFormBody,
    RestJsonBody,
    RestMultipartBody,
    RestRawBody,
    RestRequest,
    RestResponse,
)


class MockRest:
    def __init__(self) -> None:
        self.calls: List[RestRequest] = []
        self.bodies: List[str] = []
        self.fail_transport = False
        self._responses: Dict[str, RestResponse] = {}
        self._specs: Dict[str, Any] = {}

    def on(
        self,
        method: str,
        path: str,
        status: int = 200,
        json_body: Any = None,
        text: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
    ) -> None:
        body = text if text is not None else ("" if json_body is None else json.dumps(json_body))
        self._specs[f"{method} {path}"] = (status, body, headers or {})

    @property
    def last(self) -> RestRequest:
        return self.calls[-1]

    async def __call__(self, request: RestRequest) -> RestResponse:
        if self.fail_transport:
            raise ConnectionError("offline")
        self.calls.append(request)
        body = request.body
        if isinstance(body, RestJsonBody):
            self.bodies.append(body.json)
        elif isinstance(body, RestRawBody):
            self.bodies.append(body.upload.content.decode("utf-8"))
        spec = self._specs.get(f"{request.method} {request.path}")
        if spec is None:
            return RestResponse.from_text(404, "no mock")
        status, text, headers = spec
        return RestResponse.from_text(status, text, headers)


async def canned_graphql(_payload: str) -> str:
    return json.dumps({"data": {"ping": "pong"}})


def client_for(rest: MockRest) -> GraphLinkClient:
    return GraphLinkClient(adapter=canned_graphql, rest_adapter=rest)


def query_string(request: RestRequest) -> str:
    return "&".join(f"{k}={v}" for k, v in request.query)


def bytes_upload(text: str, filename: Optional[str] = None, mime_type: str = "application/octet-stream") -> GLUpload:
    return GLUpload(text.encode("utf-8"), filename, mime_type)
