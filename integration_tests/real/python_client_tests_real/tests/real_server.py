import os
from typing import Optional

from generated import (
    DefaultGraphLinkWebSocketAdapter,
    GraphLinkClient,
    GraphLinkHttpxAdapter,
)

DEFAULT_PORT = 9999
UPLOAD_PORT = 9998


def http_url(port: int) -> str:
    return f"http://localhost:{port}/graphql"


def ws_url(port: int) -> str:
    return f"ws://localhost:{port}/graphql"


def new_client(port: int = DEFAULT_PORT, ws_adapter: Optional[DefaultGraphLinkWebSocketAdapter] = None) -> GraphLinkClient:
    if ws_adapter is None:
        return GraphLinkClient.with_http(url=http_url(port), ws_url=ws_url(port))
    http = GraphLinkHttpxAdapter(url=http_url(port))
    return GraphLinkClient(adapter=http.call, ws_adapter=ws_adapter)


def new_upload_client() -> GraphLinkClient:
    main = GraphLinkHttpxAdapter(url=http_url(DEFAULT_PORT))
    upload = GraphLinkHttpxAdapter(url=http_url(UPLOAD_PORT))
    return GraphLinkClient(
        adapter=main.call,
        upload_adapter=upload.multipart_call,
        ws_adapter=DefaultGraphLinkWebSocketAdapter(url=ws_url(DEFAULT_PORT)),
    )


def new_ws_adapter(port: int = DEFAULT_PORT, **kwargs) -> DefaultGraphLinkWebSocketAdapter:
    return DefaultGraphLinkWebSocketAdapter(url=ws_url(port), reconnect=True, **kwargs)


def server_jar() -> Optional[str]:
    return os.environ.get("SERVER_JAR")
