package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.interfaces.*
import dev.graphlink.test.generated.types.*
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
}
