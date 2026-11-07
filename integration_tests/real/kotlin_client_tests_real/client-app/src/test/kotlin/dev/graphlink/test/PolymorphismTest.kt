package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.inputs.*
import dev.graphlink.test.generated.interfaces.*
import dev.graphlink.test.generated.types.*
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class PolymorphismTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun aUnionMemberPerId() = runTest {
        val photo = client.queries.attachment("ph1").attachment
        val video = client.queries.attachment("v1").attachment
        val document = client.queries.attachment("d1").attachment
        assertIs<Photo>(photo)
        assertEquals(640, photo.width)
        assertEquals(30, assertIs<Video>(video).seconds)
        assertEquals(12, assertIs<Document>(document).pages)
    }

    @Test
    fun aNullableUnionDecodesNull() = runTest {
        assertNull(client.queries.attachment("nope").attachment)
    }

    @Test
    fun aListOfUnionMembers() = runTest {
        val list = client.queries.attachments().attachments
        assertIs<Photo>(list[0])
        assertIs<Video>(list[1])
        assertIs<Document>(list[2])
    }

    @Test
    fun nullElementsInAListOfUnions() = runTest {
        val list = client.queries.attachmentsNullable().attachmentsNullable!!
        assertEquals(3, list.size)
        assertIs<Photo>(list[0])
        assertNull(list[1])
        assertIs<Document>(list[2])
    }

    @Test
    fun aUnionReturnedByAMutation() = runTest {
        assertIs<Photo>(client.mutations.addAttachment("a1", "u", "photo").addAttachment)
        assertIs<Video>(client.mutations.addAttachment("a1", "u", "video").addAttachment)
        assertIs<Document>(client.mutations.addAttachment("a1", "u", "document").addAttachment)
    }

    @Test
    fun aServerErrorOnAUnionMutationThrows() = runTest {
        assertFails { client.mutations.addAttachment("a1", "u", "bogus") }
    }

    @Test
    fun aListOfAnInterfaceImplementingAnotherInterface() = runTest {
        val feed = client.queries.feed().feed
        assertIs<Article>(feed[0])
        assertIs<Comment>(feed[1])
        assertIs<Article>(feed[2])
        assertIs<Comment>(feed[3])
        assertEquals(listOf("alice", "bob", "bob", "alice"), feed.map { it.createdBy })
    }

    @Test
    fun aNullableInterfaceReturnsEachImplementationOrNull() = runTest {
        assertIs<Article>(client.queries.node("a1").node)
        assertIs<Comment>(client.queries.node("c1").node)
        assertNull(client.queries.node("zzz").node)
    }

    @Test
    fun aUnionFieldAndAListOfUnionsInsideAnObject() = runTest {
        val article = client.queries.article("a1").article
        assertIs<Photo>(article.cover)
        assertEquals(3, article.attachments.size)
        assertIs<Photo>(article.attachments[0])
        assertIs<Video>(article.attachments[1])
        assertIs<Document>(article.attachments[2])
    }

    @Test
    fun nullPolymorphicFields() = runTest {
        val article = client.queries.article("a2").article
        assertNull(article.cover)
        assertTrue(article.attachments.isEmpty())
        assertNull(article.related)
    }

    @Test
    fun nullElementsInAListOfInterfaces() = runTest {
        val related = client.queries.article("a1").article.related!!
        assertEquals(2, related.size)
        assertIs<Comment>(related[0])
        assertNull(related[1])
    }

    @Test
    fun anInterfaceFieldPointingBackAtAnImplementer() = runTest {
        val reply = client.queries.feed().feed[3]
        assertIs<Comment>(reply)
        val parent = assertIs<Article>(reply.parent)
        assertEquals("Hello", parent.title)
    }

    @Test
    fun anUnknownArticleIsAnError() = runTest {
        assertFails { client.queries.article("zzz") }
    }

    @Test
    fun capturedErrorsOnAUnionOperation() = runTest {
        val ok = client.queries.attachmentOrErrors("ph1")
        assertNull(ok.errors)
        assertIs<Photo>(ok.data!!.attachmentOrErrors)
        val failed = client.queries.attachmentOrErrors("boom")
        assertNull(failed.data!!.attachmentOrErrors)
        assertTrue(failed.errors!!.first().message.isNotEmpty())
    }

    @Test
    fun aCachedUnionOperationIsServedOnce() = runTest {
        var calls = 0
        val real = OkHttpGraphLinkClientAdapter(Fixtures.SERVER_URL)
        val counting = object : dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter {
            override suspend fun execute(payload: String): String {
                calls++
                return real.execute(payload)
            }
        }
        val codec = dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec()
        val c = GraphLinkClient(counting, MockWebSocketAdapter(), MockMultipartAdapter(), codec, codec)
        assertIs<Video>(c.queries.getCachedAttachment("v1").getCachedAttachment)
        assertIs<Video>(c.queries.getCachedAttachment("v1").getCachedAttachment)
        assertEquals(1, calls)
    }

    @Test
    fun inlineFragmentsOnEveryMemberOfAUnion() = runBlocking<Unit> {
        val photo = client.queries.fetchAttachment("ph1").attachment
        val video = client.queries.fetchAttachment("v1").attachment
        val document = client.queries.fetchAttachment("d1").attachment
        assertEquals(640, assertIs<Photo>(photo).width)
        assertEquals(30, assertIs<Video>(video).seconds)
        assertEquals(12, assertIs<Document>(document).pages)
        assertNull(client.queries.fetchAttachment("nope").attachment)
    }

    @Test
    fun oneFragmentSharedByTwoRootFields() = runBlocking<Unit> {
        val res = client.queries.fetchArticleAndAttachment("a1", "v1")
        assertEquals("ph1", res.article.cover!!.id)
        assertEquals("v1", res.attachment!!.id)
        assertEquals(30, assertIs<Video_IdSeconds>(res.attachment).seconds)
    }

    @Test
    fun anInterfaceSelectionWithInlineFragmentsAndASharedFragment() = runBlocking<Unit> {
        val feed = client.queries.fetchFeed().feed
        assertEquals(4, feed.size)
        val article = assertIs<Article_AttachmentsCoverCreatedBy_pztuu6>(feed[0])
        assertEquals("Hello", article.title)
        assertEquals("http://cdn/1.png", assertIs<Photo_IdUrl>(article.cover).url)
        assertEquals(listOf("ph1", "v1", "d1"), article.attachments.map { it.id })
        assertEquals("Nice", assertIs<Comment>(feed[1]).text)
        assertNull(assertIs<Article_AttachmentsCoverCreatedBy_pztuu6>(feed[2]).cover)
    }

    @Test
    fun anInterfaceSelectionThatNamesOnlySomeImplementers() = runBlocking<Unit> {
        val article = assertIs<Article_CreatedByIdTitle>(client.queries.fetchNode("a1").node)
        assertEquals("Hello", article.title)
        assertEquals("alice", article.createdBy)
        val comment = assertIs<Comment_CreatedById>(client.queries.fetchNode("c1").node)
        assertEquals("bob", comment.createdBy)
        assertNull(client.queries.fetchNode("nope").node)
    }

    @Test
    fun twoQueriesSelectDifferentShapesOfTheSameUnion() = runBlocking<Unit> {
        val photo = assertIs<Photo>(client.queries.fetchPhotoParts("ph1").attachment)
        assertEquals(640, photo.width)
        assertEquals("http://cdn/1.png", photo.url)
        assertEquals("v1", assertIs<Video_Id>(client.queries.fetchPhotoParts("v1").attachment).id)
        assertEquals(640, assertIs<Photo>(client.queries.fetchAttachment("ph1").attachment).width)
    }

    @Test
    fun anAliasKeepsBothTypesOfASharedFieldReadable() = runBlocking<Unit> {
        assertEquals(6, assertIs<Phone_IdSize>(client.queries.fetchGadget("p1").gadget).size)
        assertEquals("15 inch", assertIs<Laptop_IdSize>(client.queries.fetchGadget("l1").gadget).laptopSize)
        assertNull(client.queries.fetchGadget("nope").gadget)
        val gadgets = client.queries.fetchGadgets().gadgets
        assertIs<Phone_IdSize>(gadgets[0])
        assertIs<Laptop_IdSize>(gadgets[1])
    }

    @Test
    fun aTypeInTwoUnionsDecodesThroughBoth() = runBlocking<Unit> {
        assertIs<Photo>(client.queries.shareable("ph1").shareable)
        assertIs<Photo>(client.queries.attachment("ph1").attachment)
        assertEquals("Pixel", assertIs<Phone>(client.queries.shareable("p1").shareable).model)
        assertNull(client.queries.shareable("nope").shareable)
    }

    @Test
    fun aUnionStreamEmitsEachMember() = runBlocking<Unit> {
        val ws = dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter(Fixtures.WS_URL)
        try {
            val codec = dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec()
            val streaming = GraphLinkClient(OkHttpGraphLinkClientAdapter(Fixtures.SERVER_URL), ws, MockMultipartAdapter(), codec, codec)
            val events = streaming.subscriptions.attachmentAdded().take(3).toList()
            assertIs<Photo>(events[0].attachmentAdded)
            assertIs<Video>(events[1].attachmentAdded)
            assertIs<Document>(events[2].attachmentAdded)
        } finally {
            ws.close()
        }
    }

    @Test
    fun anInterfaceStreamEmitsEachImplementer() = runBlocking<Unit> {
        val ws = dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter(Fixtures.WS_URL)
        try {
            val codec = dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec()
            val streaming = GraphLinkClient(OkHttpGraphLinkClientAdapter(Fixtures.SERVER_URL), ws, MockMultipartAdapter(), codec, codec)
            val events = streaming.subscriptions.entityPublished().take(2).toList()
            assertIs<Article>(events[0].entityPublished)
            assertIs<Comment>(events[1].entityPublished)
        } finally {
            ws.close()
        }
    }

    @Test
    fun theArgumentReachesEveryImplementerAndEachKeepsItsOwnFields() = runTest {
        val album = assertIs<Album>(client.queries.listing("al1", ListingFieldArgs(itemsLimit = 2)).listing)
        assertEquals(2020, album.year)
        assertEquals(listOf("Photo", "Video"), album.items.map { it::class.simpleName })
        val playlist = assertIs<Playlist>(client.queries.listing("pl1", ListingFieldArgs(itemsLimit = 5)).listing)
        assertEquals(12, playlist.tracks)
        assertEquals(listOf("Video", "Document"), playlist.items.map { it::class.simpleName })
    }

    @Test
    fun aLimitOfZeroYieldsEmptyLists() = runTest {
        assertTrue(client.queries.listing("al1", ListingFieldArgs(itemsLimit = 0)).listing!!.items.isEmpty())
    }

    @Test
    fun theInterfaceFieldReturnsTheOtherImplementerOrNull() = runTest {
        val summer = client.queries.listing("al1", ListingFieldArgs(itemsLimit = 1)).listing!!
        assertEquals(12, assertIs<Playlist>(summer.related).tracks)
        assertNull(client.queries.listing("al2", ListingFieldArgs(itemsLimit = 1)).listing!!.related)
    }

    @Test
    fun anUnknownListingIdDecodesNull() = runTest {
        assertNull(client.queries.listing("nope", ListingFieldArgs(itemsLimit = 1)).listing)
    }

    @Test
    fun aListOfTheInterfaceDecodesEachImplementer() = runTest {
        val listings = client.queries.listings(ListingsFieldArgs(itemsLimit = 1)).listings
        assertEquals(listOf("Album", "Playlist", "Album"), listings.map { it::class.simpleName })
        assertEquals(listOf(1, 1, 1), listings.map { it.items.size })
    }

    @Test
    fun aSingleMemberUnionDecodesToTheMember() = runTest {
        val solo = assertIs<Album>(client.queries.solo(SoloFieldArgs(itemsLimit = 1)).solo)
        assertEquals("Summer", solo.title)
    }

    @Test
    fun idAndUrlAreReadableOnTheUnionItself() = runTest {
        val list = client.queries.attachments().attachments
        assertEquals(listOf("ph1", "v1", "d1"), list.map { it.id })
        assertEquals(listOf("http://cdn/1.png", "http://cdn/1.mp4", "http://cdn/1.pdf"), list.map { it.url })
    }

    @Test
    fun aSelectionThatSharesOnlySomeFieldsExposesJustThose() = runTest {
        assertEquals("ph1", client.queries.fetchPhotoParts("ph1").attachment!!.id)
        assertEquals("v1", client.queries.fetchPhotoParts("v1").attachment!!.id)
    }

    @Test
    fun aUnionOfTwoTypesSharesOnlyId() = runTest {
        assertEquals("ph1", client.queries.shareable("ph1").shareable!!.id)
        assertEquals("p1", client.queries.shareable("p1").shareable!!.id)
    }

    @Test
    fun theDirectQueryKeepsTheFullType() = runTest {
        val photo = client.queries.photo("ph1").photo!!
        assertEquals(listOf<Any>("ph1", "http://cdn/1.png", 640), listOf(photo.id, photo.url, photo.width))
        assertNull(client.queries.photo("nope").photo)
    }

    @Test
    fun aPartialSelectionOfTheSameTypeDoesNotReplaceIt() = runTest {
        assertEquals(640, client.queries.fetchPhotoWidth("ph1").photo!!.width)
        assertEquals("http://cdn/1.png", assertIs<Photo_Url>(client.queries.fetchPhotoUrl("ph1").attachment).url)
        assertIs<Video_Id>(client.queries.fetchPhotoUrl("v1").attachment)
    }

    @Test
    fun anInterfaceFragmentMixedWithConcreteOnes() = runTest {
        val results = client.queries.searchMixed("x").search
        assertEquals(listOf("user-1", "post-1"), results.map { it.id })
        assertEquals("Alice Smith", assertIs<UserResult_IdName>(results[0]).name)
        assertEquals("Hello World", assertIs<PostResult>(results[1]).title)
    }

    private suspend fun nodeTitle() = assertIs<Article>(client.queries.getCachedNode("a1").getCachedNode).title

    private suspend fun videoSeconds() = assertIs<Video>(client.queries.getCachedAttachment("v1").getCachedAttachment).seconds

    @Test
    fun aCachedInterfaceResultIsServedFromTheCache() = runTest {
        assertEquals(nodeTitle(), nodeTitle())
    }

    @Test
    fun invalidatingTheTagOfACachedInterfaceFetchesItAgain() = runTest {
        val before = nodeTitle()
        client.mutations.evictNodes()
        assertNotEquals(before, nodeTitle())
    }

    @Test
    fun invalidatingTheTagOfACachedUnionFetchesItAgain() = runTest {
        val before = videoSeconds()
        assertEquals(before, videoSeconds())
        client.mutations.evictAttachments()
        assertNotEquals(before, videoSeconds())
    }

    @Test
    fun invalidatingAnotherTagLeavesTheCachedUnionAlone() = runTest {
        val before = videoSeconds()
        client.mutations.evictNodes()
        assertEquals(before, videoSeconds())
    }
}
