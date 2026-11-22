from typing import List

from generated.errors.upload_rejected import UploadRejected
from generated.file_upload import FileUpload

from .file_utils import read_file


class PingServiceImpl:
    async def ping(self) -> bool:
        return True


class UploadOneFileServiceImpl:
    async def upload_one_file(self, user_id: str, file: FileUpload) -> bool:
        data = await read_file(file)
        if user_id == "rejected":
            raise UploadRejected(user_id=user_id, reason="quota exceeded", message="Upload rejected")
        return len(data) > 0


class UploadFileListServiceImpl:
    async def upload_file_list(self, user_id: str, files: List[FileUpload]) -> bool:
        if len(files) == 0:
            return False
        if user_id == "rejected":
            for file in files:
                await read_file(file)
            raise UploadRejected(user_id=user_id, reason="quota exceeded", message="Upload rejected")
        for file in files:
            if len(await read_file(file)) == 0:
                return False
        return True
