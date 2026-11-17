from impl.upload_services import PingServiceImpl, UploadFileListServiceImpl, UploadOneFileServiceImpl

from generated.app import GraphLinkServices

services = GraphLinkServices(
    ping_service=PingServiceImpl(),
    upload_one_file_service=UploadOneFileServiceImpl(),
    upload_file_list_service=UploadFileListServiceImpl(),
)
