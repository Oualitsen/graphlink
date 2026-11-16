import uvicorn

from generated.app import GraphLinkServices, create_app
from impl.services import PingServiceImpl, UploadFileListServiceImpl, UploadOneFileServiceImpl

PORT = 9974

services = GraphLinkServices(
    ping_service=PingServiceImpl(),
    upload_one_file_service=UploadOneFileServiceImpl(),
    upload_file_list_service=UploadFileListServiceImpl(),
)

app = create_app(services)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="warning")
