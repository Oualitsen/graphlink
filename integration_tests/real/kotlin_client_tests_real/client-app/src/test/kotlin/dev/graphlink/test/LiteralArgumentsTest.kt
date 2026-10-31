package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class LiteralArgumentsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun stringLiteral_selectsTheRightUser() = runTest {
        val user = client.queries.findFirstUser().findUser
        assertEquals("Alice Smith", user?.name)
        assertEquals("alice@test.com", user?.email)
    }

    @Test
    fun enumLiteral_filtersOnTheServer() = runTest {
        assertEquals(listOf("user-1"), client.queries.listActiveUsers().listUsersByStatus.map { it.id })
    }

    @Test
    fun severalLiterals_inOneField_areApplied() = runTest {
        assertEquals(listOf("Alice Smith"), client.queries.searchAlice().searchUsers.map { it.name })
    }

    @Test
    fun inlineLimit_isEnforced_whileTheOtherArgumentStaysAVariable() = runTest {
        assertEquals(1, client.queries.searchWithFixedLimit("s").searchUsers.size)
    }

    @Test
    fun dollarSigns_insideALiteral_formAValidQuery() = runTest {
        assertTrue(client.queries.searchPrice().searchUsers.isEmpty())
    }
}
