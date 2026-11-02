package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.enums.Status
import dev.graphlink.rest.generated.types.Cat
import dev.graphlink.rest.generated.types.Dog
import dev.graphlink.rest.generated.types.Owner
import dev.graphlink.rest.generated.types.Product
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ResponsesTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient()
    }

    @Test
    fun okStatusesDecode() = runBlocking {
        assertEquals("Pen", client.queries.status(code = 200)!!.name)
        assertEquals("p1", client.queries.status(code = 201)!!.id)
    }

    @Test
    fun noContentIsNullOrADecodeError() = runBlocking {
        assertNull(client.queries.status(code = 204))
        assertFailsWith<IllegalStateException> { client.queries.statusNonNull(code = 204) }
        Unit
    }

    @Test
    fun errorStatusesRaiseRestError() = runBlocking {
        for (code in listOf(400, 401, 403, 404, 409, 422, 500, 502, 503)) {
            val error = assertFailsWith<RestError> { client.queries.status(code = code) }
            assertEquals(code, error.status)
            assertTrue(error.body.contains("status $code"))
            assertEquals("reason-$code", error.headers["x-reason"])
        }
        val teapot = assertFailsWith<RestError> { client.queries.status(code = 418) }
        assertTrue(teapot.toString().contains("418"))
        assertEquals("p1", client.queries.status(code = 200)!!.id)
    }

    @Test
    fun emptyBodies() = runBlocking {
        assertNull(client.queries.blank())
        assertFailsWith<IllegalStateException> { client.queries.blankNonNull() }
        assertNull(client.queries.noContent())
        assertNull(client.queries.textOptional())
        assertNull(client.queries.jsonNull())
        Unit
    }

    @Test
    fun valueKinds() = runBlocking {
        assertEquals(7, client.queries.count())
        assertEquals(true, client.queries.flag())
        assertEquals("héllo ✓", client.queries.text())
        assertEquals(listOf(1, 2, 3), client.queries.deep())
        assertEquals(listOf("p1", "p2"), client.queries.wrapped().map { it.id })
        val unicode = client.queries.unicode()
        assertEquals("é漢😀 \"quoted\"", unicode.name)
        assertEquals(listOf("ß"), unicode.tags)
        val extra = client.queries.extraKeys()
        assertEquals("x", extra.id)
        assertNull(extra.tags)
    }

    @Test
    fun missingNonNullFieldIsANamedError() = runBlocking {
        val error = assertFailsWith<IllegalArgumentException> { client.queries.missingField() }
        assertEquals("Product.name is missing or null in the response", error.message)
        Unit
    }

    @Test
    fun nestedTypesEnumsAndCycles() = runBlocking {
        val p: Product = client.queries.product(id = "p1")!!
        assertEquals(Status.ACTIVE, p.status)
        assertEquals("Book", p.related!!.single().name)
        assertNull(p.related!!.single().related)
    }

    @Test
    fun interfacesAndUnionsDecodeThroughTheirDiscriminator() = runBlocking {
        val pets = client.queries.pets()
        assertIs<Dog>(pets[0])
        assertTrue((pets[0] as Dog).barks)
        assertIs<Cat>(pets[1])
        assertEquals(9, (pets[1] as Cat).lives)
        val pet = client.queries.pet(id = "c1")
        assertIs<Cat>(pet)
        assertEquals("Tom", pet.name)
        val error = assertThrows<IllegalArgumentException> { runBlocking { client.queries.petsUnknown() } }
        assertTrue(error.message!!.contains("bird"))
        val hits = client.queries.hits()
        assertIs<Product>(hits[0])
        assertIs<Owner>(hits[1])
    }

    @Test
    fun graphQlAndRestShareOneClient() = runBlocking {
        assertEquals(19, client.queries.getCount().getCount)
        assertEquals(7, client.queries.count())
        assertEquals(19, client.queries.getCount().getCount)
    }

    @Test
    fun downloads() = runBlocking {
        val d = client.queries.blob(size = 100000)
        assertEquals("blob-100000.bin", d.filename)
        assertTrue(d.contentType!!.startsWith("application/octet-stream"))
        assertEquals(100000L, d.length)
        assertContentEquals(pattern(100000), d.bytes())

        val big = client.queries.blob(size = 8 * 1024 * 1024)
        val buffer = ByteArray(65536)
        var received = 0
        var reads = 0
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        big.stream.use { s ->
            while (true) {
                val n = s.read(buffer)
                if (n < 0) break
                received += n
                reads++
                digest.update(buffer, 0, n)
            }
        }
        assertEquals(8 * 1024 * 1024, received)
        assertTrue(reads > 1)
        assertEquals(sha256Of(pattern(8 * 1024 * 1024)), digest.digest().joinToString("") { "%02x".format(it) })

        val reports = mutableListOf<LongArray>()
        client.queries.blob(size = 500000, onReceiveProgress = DownloadProgressCallback { r, t -> reports.add(longArrayOf(r, t)) }).bytes()
        assertEquals(listOf(500000L, 500000L), reports.last().toList())
        for (i in 1 until reports.size) assertTrue(reports[i][0] >= reports[i - 1][0])
        assertEquals(0, client.queries.blob(size = 0).bytes().size)
    }

    @Test
    fun missingDownloadAndRoundTrip() = runBlocking {
        assertEquals(404, assertFailsWith<RestError> { client.queries.avatar(id = "p1") }.status)
        val bytes = pattern(70000)
        client.mutations.uploadAvatar(id = "p1", file = uploadOf(bytes, mimeType = "image/png"))
        val d = client.queries.avatar(id = "p1")
        assertTrue(d.contentType!!.startsWith("image/png"))
        assertEquals("p1.png", d.filename)
        assertContentEquals(bytes, d.bytes())
    }

    @Test
    fun nullableDownloadIsNullOnNoContent() = runBlocking {
        assertNull(client.queries.avatarOrEmpty(id = "p1"))
        client.mutations.uploadAvatar(id = "p1", file = uploadOf(pattern(10)))
        assertContentEquals(pattern(10), client.queries.avatarOrEmpty(id = "p1")!!.bytes())
    }
}
