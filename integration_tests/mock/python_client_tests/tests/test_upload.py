import json
import unittest
from typing import List

from generated import GLUpload, GraphLinkClient

from . import fixtures as fx
from .mock_adapter import MockAdapter, MockMultipartAdapter, MockWebSocketAdapter


def make_file(content: bytes, filename: str = None) -> GLUpload:
    return GLUpload.from_bytes(content, filename=filename, mime_type="image/png")


class UploadTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.multipart = MockMultipartAdapter()
        self.client = GraphLinkClient(
            adapter=self.adapter.call, upload_adapter=self.multipart.call, ws_adapter=MockWebSocketAdapter()
        )

    def operations(self):
        return json.loads(self.multipart.last_call["operations"])

    def file_map(self):
        return json.loads(self.multipart.last_call["map"])

    async def test_single_file_response(self) -> None:
        self.multipart.register_data("uploadOneFile", {"uploadOneFile": fx.USER_ALICE})
        res = await self.client.mutations.upload_one_file(user_id="user-1", file=make_file(b"\x01\x02\x03"))
        self.assertEqual(res.upload_one_file.id, "user-1")
        self.assertEqual(res.upload_one_file.name, "Alice Smith")
        self.assertEqual(self.multipart.call_count, 1)
        self.assertEqual(self.adapter.call_count, 0)

    async def test_single_file_multipart_shape(self) -> None:
        self.multipart.register_data("uploadOneFile", {"uploadOneFile": fx.USER_ALICE})
        await self.client.mutations.upload_one_file(user_id="user-42", file=make_file(b"\x01\x02\x03"))
        self.assertEqual(self.operations()["variables"]["userId"], "user-42")
        self.assertIsNone(self.operations()["variables"]["file"])
        self.assertEqual(self.file_map()["0"], ["variables.file"])
        self.assertIn("0", self.multipart.last_call)
        self.assertIsInstance(self.multipart.last_call["0"], GLUpload)

    async def test_file_list_response_and_shape(self) -> None:
        self.multipart.register_data("uploadFileList", {"uploadFileList": fx.USER_ALICE})
        files: List[GLUpload] = [make_file(b"\x01"), make_file(b"\x02")]
        res = await self.client.mutations.upload_file_list(user_id="user-1", files=files)
        self.assertEqual(res.upload_file_list.id, "user-1")
        self.assertEqual(self.operations()["variables"]["files"], [None, None])
        self.assertEqual(self.file_map()["0"], ["variables.files.0"])
        self.assertEqual(self.file_map()["1"], ["variables.files.1"])
        self.assertIn("0", self.multipart.last_call)
        self.assertIn("1", self.multipart.last_call)

    async def test_single_item_list_produces_one_slot(self) -> None:
        self.multipart.register_data("uploadFileList", {"uploadFileList": fx.USER_ALICE})
        await self.client.mutations.upload_file_list(user_id="user-1", files=[make_file(b"\x01")])
        self.assertEqual(len(self.file_map()), 1)


if __name__ == "__main__":
    unittest.main()
