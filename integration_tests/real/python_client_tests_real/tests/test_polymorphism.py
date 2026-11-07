import asyncio
import unittest

from generated import (
    Album,
    Article,
    Comment,
    DefaultGraphLinkWebSocketAdapter,
    Document,
    GraphLinkClient,
    GraphLinkHttpxAdapter,
    ListingFieldArgs,
    ListingsFieldArgs,
    Photo,
    Playlist,
    SoloFieldArgs,
    Video,
)

from .real_server import DEFAULT_PORT, http_url, new_client, new_ws_adapter, ws_url


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


class CustomQueries(RealTestCase):
    async def test_inline_fragments_on_every_member_of_a_union(self) -> None:
        photo = (await self.client.queries.fetch_attachment(id="ph1")).attachment
        video = (await self.client.queries.fetch_attachment(id="v1")).attachment
        document = (await self.client.queries.fetch_attachment(id="d1")).attachment
        self.assertEqual(photo.width, 640)
        self.assertEqual(video.seconds, 30)
        self.assertEqual(document.pages, 12)
        self.assertIsNone((await self.client.queries.fetch_attachment(id="nope")).attachment)

    async def test_one_fragment_shared_by_two_root_fields(self) -> None:
        res = await self.client.queries.fetch_article_and_attachment(article_id="a1", attachment_id="v1")
        self.assertEqual(res.article.cover.id, "ph1")
        self.assertEqual(res.attachment.id, "v1")
        self.assertEqual(res.attachment.seconds, 30)


class DifferentShapesOfOneAbstractType(RealTestCase):
    async def test_an_interface_selection_with_inline_fragments_and_a_shared_fragment(self) -> None:
        feed = (await self.client.queries.fetch_feed()).feed
        self.assertEqual([getattr(e, "title", None) for e in feed], ["Hello", None, "Second", None])
        self.assertEqual([getattr(e, "text", None) for e in feed], [None, "Nice", None, "Thanks"])
        self.assertEqual(feed[0].cover.url, "http://cdn/1.png")
        self.assertEqual([a.id for a in feed[0].attachments], ["ph1", "v1", "d1"])
        self.assertIsNone(feed[2].cover)

    async def test_an_interface_selection_that_names_only_some_implementers(self) -> None:
        article = (await self.client.queries.fetch_node(id="a1")).node
        self.assertEqual(article.title, "Hello")
        self.assertEqual(article.created_by, "alice")
        comment = (await self.client.queries.fetch_node(id="c1")).node
        self.assertEqual(comment.created_by, "bob")
        self.assertFalse(hasattr(comment, "title"))
        self.assertIsNone((await self.client.queries.fetch_node(id="nope")).node)

    async def test_two_queries_select_different_shapes_of_the_same_union(self) -> None:
        photo = (await self.client.queries.fetch_photo_parts(id="ph1")).attachment
        self.assertEqual(photo.width, 640)
        self.assertEqual(photo.url, "http://cdn/1.png")
        video = (await self.client.queries.fetch_photo_parts(id="v1")).attachment
        self.assertEqual(video.id, "v1")
        self.assertFalse(hasattr(video, "seconds"))
        full = (await self.client.queries.fetch_attachment(id="ph1")).attachment
        self.assertEqual(full.width, 640)


class SameFieldDifferentTypes(RealTestCase):
    async def test_an_alias_keeps_both_types_readable(self) -> None:
        phone = (await self.client.queries.fetch_gadget(id="p1")).gadget
        laptop = (await self.client.queries.fetch_gadget(id="l1")).gadget
        self.assertEqual(phone.size, 6)
        self.assertEqual(laptop.laptop_size, "15 inch")
        self.assertIsNone((await self.client.queries.fetch_gadget(id="nope")).gadget)

    async def test_a_list_of_both_members(self) -> None:
        gadgets = (await self.client.queries.fetch_gadgets()).gadgets
        self.assertEqual([g.id for g in gadgets], ["p1", "l1"])
        self.assertEqual(gadgets[0].size, 6)
        self.assertEqual(gadgets[1].laptop_size, "15 inch")


class TypeInTwoUnions(RealTestCase):
    async def test_photo_decodes_through_shareable_and_through_attachment(self) -> None:
        self.assertIsInstance((await self.client.queries.shareable(id="ph1")).shareable, Photo)
        self.assertIsInstance((await self.client.queries.attachment(id="ph1")).attachment, Photo)

    async def test_phone_decodes_through_shareable(self) -> None:
        shareable = (await self.client.queries.shareable(id="p1")).shareable
        self.assertEqual(shareable.model, "Pixel")
        self.assertEqual(shareable.size, 6)
        self.assertIsNone((await self.client.queries.shareable(id="nope")).shareable)


class InterfaceWithFieldArgument(RealTestCase):
    async def test_the_argument_reaches_every_implementer_and_each_keeps_its_own_fields(self) -> None:
        album = (await self.client.queries.listing(id="al1", field_args=ListingFieldArgs(items_limit=2))).listing
        self.assertIsInstance(album, Album)
        self.assertEqual(album.year, 2020)
        self.assertEqual([type(a) for a in album.items], [Photo, Video])
        playlist = (await self.client.queries.listing(id="pl1", field_args=ListingFieldArgs(items_limit=5))).listing
        self.assertEqual(playlist.tracks, 12)
        self.assertEqual([type(a) for a in playlist.items], [Video, Document])

    async def test_a_limit_of_zero_yields_empty_lists(self) -> None:
        album = (await self.client.queries.listing(id="al1", field_args=ListingFieldArgs(items_limit=0))).listing
        self.assertEqual(list(album.items), [])

    async def test_the_interface_field_returns_the_other_implementer_or_null(self) -> None:
        album = (await self.client.queries.listing(id="al1", field_args=ListingFieldArgs(items_limit=1))).listing
        self.assertIsInstance(album.related, Playlist)
        self.assertEqual(album.related.tracks, 12)
        winter = (await self.client.queries.listing(id="al2", field_args=ListingFieldArgs(items_limit=1))).listing
        self.assertIsNone(winter.related)

    async def test_an_unknown_id_decodes_null(self) -> None:
        response = await self.client.queries.listing(id="nope", field_args=ListingFieldArgs(items_limit=1))
        self.assertIsNone(response.listing)

    async def test_a_list_of_the_interface_decodes_each_implementer(self) -> None:
        listings = (await self.client.queries.listings(field_args=ListingsFieldArgs(items_limit=1))).listings
        self.assertEqual([type(l) for l in listings], [Album, Playlist, Album])
        self.assertEqual([len(l.items) for l in listings], [1, 1, 1])


class SingleMemberUnion(RealTestCase):
    async def test_decodes_to_the_member(self) -> None:
        solo = (await self.client.queries.solo(field_args=SoloFieldArgs(items_limit=1))).solo
        self.assertIsInstance(solo, Album)
        self.assertEqual(solo.title, "Summer")


class SharedFieldSameType(RealTestCase):
    async def test_id_and_url_are_readable_on_the_union_itself(self) -> None:
        attachments = (await self.client.queries.attachments()).attachments
        self.assertEqual([a.id for a in attachments], ["ph1", "v1", "d1"])
        self.assertEqual([a.url for a in attachments], ["http://cdn/1.png", "http://cdn/1.mp4", "http://cdn/1.pdf"])

    async def test_a_selection_that_shares_only_some_fields_exposes_just_those(self) -> None:
        self.assertEqual((await self.client.queries.fetch_photo_parts(id="ph1")).attachment.id, "ph1")
        self.assertEqual((await self.client.queries.fetch_photo_parts(id="v1")).attachment.id, "v1")

    async def test_a_union_of_two_types_shares_only_id(self) -> None:
        self.assertEqual((await self.client.queries.shareable(id="ph1")).shareable.id, "ph1")
        self.assertEqual((await self.client.queries.shareable(id="p1")).shareable.id, "p1")


class MemberReturnedDirectlyAndProjected(RealTestCase):
    async def test_the_direct_query_keeps_the_full_type(self) -> None:
        photo = (await self.client.queries.photo(id="ph1")).photo
        self.assertEqual([photo.id, photo.url, photo.width], ["ph1", "http://cdn/1.png", 640])
        self.assertIsNone((await self.client.queries.photo(id="nope")).photo)

    async def test_a_partial_selection_of_the_same_type_does_not_replace_it(self) -> None:
        self.assertEqual((await self.client.queries.fetch_photo_width(id="ph1")).photo.width, 640)
        member = (await self.client.queries.fetch_photo_url(id="ph1")).attachment
        self.assertEqual(member.url, "http://cdn/1.png")
        self.assertEqual((await self.client.queries.fetch_photo_url(id="v1")).attachment.id, "v1")


class InterfaceFragmentMixedWithConcreteOnes(RealTestCase):
    async def test_the_interface_fields_reach_every_member_and_the_concrete_ones_their_own(self) -> None:
        results = (await self.client.queries.search_mixed(term="x")).search
        self.assertEqual([r.id for r in results], ["user-1", "post-1"])
        self.assertEqual(results[0].name, "Alice Smith")
        self.assertEqual(results[1].title, "Hello World")


class PolymorphicSubscriptions(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.ws = new_ws_adapter()
        self.client = new_client(ws_adapter=self.ws)

    async def asyncTearDown(self) -> None:
        await self.ws.close()

    async def _take(self, stream, count):
        events = []
        try:
            while len(events) < count:
                events.append(await asyncio.wait_for(stream.__anext__(), 10))
        finally:
            await stream.aclose()
        return events

    async def test_a_union_stream_emits_each_member(self) -> None:
        events = await self._take(self.client.subscriptions.attachment_added(), 3)
        self.assertEqual([type(e.attachment_added) for e in events], [Photo, Video, Document])

    async def test_an_interface_stream_emits_each_implementer(self) -> None:
        events = await self._take(self.client.subscriptions.entity_published(), 2)
        self.assertEqual([type(e.entity_published) for e in events], [Article, Comment])
