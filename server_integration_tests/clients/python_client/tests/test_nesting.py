import unittest

from generated import Color, Photo, Video

from .fixtures import new_client


class NestingTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_enum_list_depths(self) -> None:
        q = self.client.queries
        self.assertEqual((await q.colors1()).colors1, [Color.RED, Color.GREEN, Color.BLUE])
        self.assertEqual((await q.colors2()).colors2, [[Color.RED], [Color.GREEN, Color.BLUE]])
        self.assertEqual((await q.colors3()).colors3, [[[Color.RED]]])

    async def test_type_list_depths(self) -> None:
        q = self.client.queries
        self.assertEqual(len((await q.boxes1()).boxes1), 2)
        self.assertEqual(len((await q.boxes2()).boxes2), 2)
        self.assertEqual((await q.boxes3()).boxes3[0][0][0].id, "b1")

    async def test_interface_list_depths(self) -> None:
        q = self.client.queries
        self.assertTrue({"circle", "square"} <= {s.kind for s in (await q.shapes1()).shapes1})
        self.assertIsNotNone((await q.shapes3()).shapes3[0][0][0].kind)

    async def test_union_list_depths(self) -> None:
        q = self.client.queries
        m1 = (await q.media1()).media1
        self.assertEqual(len(m1), 2)
        photos = [m for m in m1 if isinstance(m, Photo)]
        videos = [m for m in m1 if isinstance(m, Video)]
        self.assertEqual((len(photos), photos[0].width), (1, 640))
        self.assertEqual((len(videos), videos[0].duration_sec), (1, 30))
        self.assertIsNotNone((await q.media3()).media3[0][0][0].url)
