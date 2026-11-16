package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class ErrorDetailsTest {

    private val client = newRealClient()

    @Test
    fun errorCarriesMessagePathLocationsAndTypedExtensions() = runTest {
        val res = client.queries.getUserOrErrors("missing")
        assertEquals(1, res.errors!!.size)
        val e = res.errors!![0]
        assertEquals("User not found: missing", e.message)
        assertEquals(listOf<Any>("getUserOrErrors"), e.path)
        assertEquals(1, e.locations!![0].line)
        assertEquals("NOT_FOUND", e.extensions!!["code"])
        assertEquals(false, e.extensions!!["retryable"])
        val detail = e.extensions!!["detail"] as Map<*, *>
        assertEquals("missing", detail["id"])
        assertEquals(3, (detail["attempts"] as Number).toInt())
    }

    @Test
    fun partialDataOkIsReturnedBadIsNullAndTheErrorPathIsTheAlias() = runTest {
        val res = client.queries.partialAliased()
        assertEquals("user-1", res.data!!.ok.id)
        assertNull(res.data!!.bad)
        assertEquals(1, res.errors!!.size)
        assertEquals(listOf<Any>("bad"), res.errors!![0].path)
    }
}
