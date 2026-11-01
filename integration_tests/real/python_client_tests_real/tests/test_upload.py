import unittest

from generated import GLUpload

from .real_server import new_upload_client


def make_file(content: bytes) -> GLUpload:
    return GLUpload.from_bytes(content, filename="file.png", mime_type="image/png")


class RealUploadTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_upload_client()

    async def test_upload_one_file(self) -> None:
        for user_id, content in (("user-1", b"\x01\x02\x03"), ("user-2", b"x"), ("user-3", bytes(range(256)) * 400)):
            res = await self.client.mutations.upload_one_file(user_id=user_id, file=make_file(content))
            self.assertIs(res.upload_one_file, True)

    async def test_upload_file_list(self) -> None:
        for count in (1, 2, 3):
            files = [make_file(bytes([i, i + 1])) for i in range(count)]
            res = await self.client.mutations.upload_file_list(user_id="user-1", files=files)
            self.assertIs(res.upload_file_list, True)

    async def test_progress_callback_is_reported(self) -> None:
        reports = []
        await self.client.mutations.upload_one_file(
            user_id="user-1", file=make_file(b"\x01\x02\x03"), on_progress=lambda sent, total: reports.append((sent, total))
        )
        self.assertEqual(reports[-1][0], reports[-1][1])


if __name__ == "__main__":
    unittest.main()
