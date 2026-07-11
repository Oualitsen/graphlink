package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.enums.Color
import dev.graphlink.server.generated.types.Photo
import dev.graphlink.server.generated.types.Video
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class NestingTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun enumListDepths123() = runTest {
        assertEquals(listOf(Color.RED, Color.GREEN, Color.BLUE), client.queries.colors1().colors1)
        assertEquals(
            listOf(listOf(Color.RED), listOf(Color.GREEN, Color.BLUE)),
            client.queries.colors2().colors2,
        )
        assertEquals(
            listOf(listOf(listOf(Color.RED))),
            client.queries.colors3().colors3,
        )
    }

    @Test
    fun typeListDepths123() = runTest {
        val b1 = client.queries.boxes1().boxes1
        assertEquals(2, b1!!.size)

        val b2 = client.queries.boxes2().boxes2
        assertEquals(2, b2.size)

        val b3 = client.queries.boxes3().boxes3
        assertEquals("b1", b3!!.first()!!.first()!!.first()!!.id)
    }

    @Test
    fun interfaceListDepths123() = runTest {
        val s1 = client.queries.shapes1().shapes1
        assertTrue(s1.map { it.kind }.containsAll(listOf("circle", "square")))

        val s3 = client.queries.shapes3().shapes3
        assertNotNull(s3.first().first().first().kind)
    }

    @Test
    fun unionListDepths123() = runTest {
        val m1 = client.queries.media1().media1
        assertEquals(2, m1.size)
        val photo = m1.filterIsInstance<Photo>().single()
        assertEquals(640, photo.width)
        val video = m1.filterIsInstance<Video>().single()
        assertEquals(30, video.durationSec)

        val m3 = client.queries.media3().media3
        assertNotNull(m3.first().first().first().url)
    }
}
