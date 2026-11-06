import unittest

from generated import (
    Article,
    Comment,
    DefaultGraphLinkWebSocketAdapter,
    Document,
    GraphLinkClient,
    GraphLinkHttpxAdapter,
    Photo,
    Video,
)

from .real_server import DEFAULT_PORT, http_url, new_client, ws_url


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()


class UnionResults(RealTestCase):
    async def test_a_union_member_per_id(self) -> None:
        photo = (await self.client.queries.attachment(id="ph1")).attachment
        video = (await self.client.queries.attachment(id="v1")).attachment
        document = (await self.client.queries.attachment(id="d1")).attachment
        self.assertIsInstance(photo, Photo)
        self.assertEqual(photo.width, 640)
        self.assertEqual(video.seconds, 30)
        self.assertEqual(document.pages, 12)

    async def test_a_nullable_union_decodes_null(self) -> None:
        self.assertIsNone((await self.client.queries.attachment(id="nope")).attachment)

    async def test_a_list_of_union_members(self) -> None:
        attachments = (await self.client.queries.attachments()).attachments
        self.assertEqual([type(a) for a in attachments], [Photo, Video, Document])

    async def test_null_elements_in_a_list_of_unions(self) -> None:
        attachments = (await self.client.queries.attachments_nullable()).attachments_nullable
        self.assertEqual(len(attachments), 3)
        self.assertIsInstance(attachments[0], Photo)
        self.assertIsNone(attachments[1])
        self.assertIsInstance(attachments[2], Document)

    async def test_a_union_returned_by_a_mutation(self) -> None:
        for kind, expected in (("photo", Photo), ("video", Video), ("document", Document)):
            with self.subTest(kind=kind):
                created = (await self.client.mutations.add_attachment(article_id="a1", url="u", kind=kind)).add_attachment
                self.assertIsInstance(created, expected)

    async def test_a_server_error_on_a_union_mutation_raises(self) -> None:
        with self.assertRaises(Exception):
            await self.client.mutations.add_attachment(article_id="a1", url="u", kind="bogus")


class InterfaceResults(RealTestCase):
    async def test_a_list_of_an_interface_implementing_another_interface(self) -> None:
        feed = (await self.client.queries.feed()).feed
        self.assertEqual([type(e) for e in feed], [Article, Comment, Article, Comment])
        self.assertEqual([e.created_by for e in feed], ["alice", "bob", "bob", "alice"])

    async def test_a_nullable_interface_returns_each_implementation_or_null(self) -> None:
        self.assertIsInstance((await self.client.queries.node(id="a1")).node, Article)
        self.assertIsInstance((await self.client.queries.node(id="c1")).node, Comment)
        self.assertIsNone((await self.client.queries.node(id="zzz")).node)


class Nesting(RealTestCase):
    async def test_a_union_field_and_a_list_of_unions_inside_an_object(self) -> None:
        article = (await self.client.queries.article(id="a1")).article
        self.assertIsInstance(article.cover, Photo)
        self.assertEqual([type(a) for a in article.attachments], [Photo, Video, Document])

    async def test_null_polymorphic_fields(self) -> None:
        article = (await self.client.queries.article(id="a2")).article
        self.assertIsNone(article.cover)
        self.assertEqual(article.attachments, [])
        self.assertIsNone(article.related)

    async def test_null_elements_in_a_list_of_interfaces(self) -> None:
        related = (await self.client.queries.article(id="a1")).article.related
        self.assertEqual(len(related), 2)
        self.assertIsInstance(related[0], Comment)
        self.assertIsNone(related[1])

    async def test_an_interface_field_pointing_back_at_an_implementer(self) -> None:
        reply = (await self.client.queries.feed()).feed[3]
        self.assertIsInstance(reply.parent, Article)
        self.assertEqual(reply.parent.title, "Hello")


class ErrorsAndCaching(RealTestCase):
    async def test_an_unknown_article_is_an_error(self) -> None:
        with self.assertRaises(Exception):
            await self.client.queries.article(id="zzz")

    async def test_captured_errors_on_a_union_operation(self) -> None:
        ok = await self.client.queries.attachment_or_errors(id="ph1")
        self.assertIsNone(ok.errors)
        self.assertIsInstance(ok.data.attachment_or_errors, Photo)
        failed = await self.client.queries.attachment_or_errors(id="boom")
        self.assertIsNone(failed.data.attachment_or_errors)
        self.assertTrue(failed.errors[0].message)

    async def test_a_cached_union_operation_is_served_once(self) -> None:
        calls = 0
        http = GraphLinkHttpxAdapter(url=http_url(DEFAULT_PORT))

        async def counting(payload: str) -> str:
            nonlocal calls
            calls += 1
            return await http.call(payload)

        client = GraphLinkClient(adapter=counting, ws_adapter=DefaultGraphLinkWebSocketAdapter(url=ws_url(DEFAULT_PORT)))
        first = (await client.queries.get_cached_attachment(id="v1")).get_cached_attachment
        second = (await client.queries.get_cached_attachment(id="v1")).get_cached_attachment
        self.assertIsInstance(first, Video)
        self.assertIsInstance(second, Video)
        self.assertEqual(calls, 1)
