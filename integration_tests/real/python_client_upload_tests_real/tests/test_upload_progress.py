import asyncio
import os
import unittest
from typing import AsyncIterator, List, Tuple

from generated import GLUpload, GraphLinkClient

from .recording_server import RecordingServer, sha256_of


def pattern(size: int) -> bytes:
    return bytes((i * 31 + 7) % 251 for i in range(size))


async def chunks(data: bytes, size: int = 65536) -> AsyncIterator[bytes]:
    for offset in range(0, len(data), size):
        yield data[offset : offset + size]


def file_of(data: bytes, filename: str, known_length: bool = True) -> GLUpload:
    return GLUpload.from_stream(chunks(data), filename=filename, length=len(data) if known_length else None)


class UploadProgressTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.server = RecordingServer()
        self.client = GraphLinkClient.with_http(url=self.server.url)

    def tearDown(self) -> None:
        self.server.close()

    async def test_a_6mb_file_arrives_intact_without_progress(self) -> None:
        data = pattern(6 * 1024 * 1024)
        res = await self.client.mutations.upload_one_file(user_id="u1", file=file_of(data, "big.bin"))
        self.assertTrue(res.upload_one_file)
        sent = self.server.only()
        self.assertEqual(sent.part("0").sha256, sha256_of(data))
        self.assertEqual(sent.part("0").filename, "big.bin")
        self.assertIn('"userId":"u1"', sent.part("operations").text.replace(" ", ""))

    async def test_a_file_of_known_length_is_sent_with_a_content_length(self) -> None:
        data = pattern(300000)
        await self.client.mutations.upload_one_file(user_id="u1", file=file_of(data, "a.bin"))
        sent = self.server.only()
        self.assertFalse(sent.chunked)
        self.assertGreater(sent.content_length, len(data))

    async def test_a_file_of_unknown_length_arrives_intact_sent_chunked(self) -> None:
        data = pattern(300000)
        await self.client.mutations.upload_one_file(user_id="u1", file=file_of(data, "a.bin", False))
        sent = self.server.only()
        self.assertEqual(sent.part("0").sha256, sha256_of(data))
        self.assertTrue(sent.chunked)

    async def test_a_6mb_file_arrives_intact_with_progress(self) -> None:
        data = pattern(6 * 1024 * 1024)
        await self.client.mutations.upload_one_file(user_id="u1", file=file_of(data, "big.bin"), on_progress=lambda s, t: None)
        self.assertEqual(self.server.only().part("0").sha256, sha256_of(data))

    async def test_progress_increases_and_ends_at_the_total(self) -> None:
        data = pattern(6 * 1024 * 1024)
        reports: List[Tuple[int, int]] = []
        await self.client.mutations.upload_one_file(
            user_id="u1", file=file_of(data, "big.bin"), on_progress=lambda s, t: reports.append((s, t))
        )
        self.assertGreater(len(reports), 10)
        for before, after in zip(reports, reports[1:]):
            self.assertGreaterEqual(after[0], before[0])
        self.assertEqual(reports[-1][0], reports[-1][1])
        self.assertGreater(reports[-1][1], len(data))
        self.assertEqual(reports[-1][1], self.server.only().content_length)

    async def test_the_file_is_not_read_in_full_before_the_first_progress_report(self) -> None:
        data = pattern(6 * 1024 * 1024)
        chunk = 65536
        pulled = 0
        pulled_at_first_report = -1

        async def slow() -> AsyncIterator[bytes]:
            nonlocal pulled
            for offset in range(0, len(data), chunk):
                if offset % (256 * 1024) == 0:
                    await asyncio.sleep(0.002)
                pulled = offset + chunk
                yield data[offset : offset + chunk]

        def on_progress(sent: int, total: int) -> None:
            nonlocal pulled_at_first_report
            if pulled_at_first_report < 0:
                pulled_at_first_report = pulled

        await self.client.mutations.upload_one_file(
            user_id="u1", file=GLUpload.from_stream(slow(), filename="big.bin", length=len(data)), on_progress=on_progress
        )
        self.assertGreaterEqual(pulled_at_first_report, 0)
        self.assertLess(pulled_at_first_report, len(data))

    async def test_a_file_of_unknown_length_fires_no_progress_and_arrives_intact(self) -> None:
        data = pattern(300000)
        reports: List[Tuple[int, int]] = []
        await self.client.mutations.upload_one_file(
            user_id="u1", file=file_of(data, "a.bin", False), on_progress=lambda s, t: reports.append((s, t))
        )
        sent = self.server.only()
        self.assertEqual(sent.part("0").sha256, sha256_of(data))
        self.assertTrue(sent.chunked)
        self.assertEqual(reports, [])

    async def test_two_files_arrive_intact_in_slot_order_with_progress(self) -> None:
        first = pattern(1200000)
        second = pattern(900000)[::-1]
        reports: List[Tuple[int, int]] = []
        res = await self.client.mutations.upload_file_list(
            user_id="u1",
            files=[file_of(first, "a.bin"), file_of(second, "b.bin")],
            on_progress=lambda s, t: reports.append((s, t)),
        )
        self.assertTrue(res.upload_file_list)
        sent = self.server.only()
        self.assertEqual(sent.part("0").sha256, sha256_of(first))
        self.assertEqual(sent.part("0").filename, "a.bin")
        self.assertEqual(sent.part("1").sha256, sha256_of(second))
        self.assertEqual(sent.part("1").filename, "b.bin")
        self.assertEqual(reports[-1][0], reports[-1][1])


@unittest.skipUnless(os.environ.get("UPLOAD_SERVER_URL"), "UPLOAD_SERVER_URL not set")
class SpringServerUploadTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = GraphLinkClient.with_http(url=os.environ["UPLOAD_SERVER_URL"])

    async def test_a_file_of_known_length_is_accepted(self) -> None:
        res = await self.client.mutations.upload_one_file(
            user_id="u1", file=file_of(pattern(3_000_000), "f.bin"), on_progress=lambda s, t: None
        )
        self.assertTrue(res.upload_one_file)

    async def test_a_file_of_unknown_length_is_accepted_chunked(self) -> None:
        res = await self.client.mutations.upload_one_file(user_id="u1", file=file_of(pattern(3_000_000), "f.bin", False))
        self.assertTrue(res.upload_one_file)

    async def test_a_list_of_files_is_accepted(self) -> None:
        res = await self.client.mutations.upload_file_list(
            user_id="u1", files=[file_of(pattern(1000), "a.bin"), file_of(pattern(2000), "b.bin", False)]
        )
        self.assertTrue(res.upload_file_list)


if __name__ == "__main__":
    unittest.main()
