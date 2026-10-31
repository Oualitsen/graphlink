package dev.graphlink.test

import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient
import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.*

class LiteralArgumentsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    private fun sentQuery(): String =
        Json.parseToJsonElement(adapter.getLastCall()!!.rawPayload).jsonObject["query"]!!.jsonPrimitive.content

    @Test
    fun stringLiteral_isSentInline_andNeedsNoParameter() = runTest {
        adapter.registerData("findFirstUser", mapOf("findUser" to kUserAliceJson))
        assertEquals("Alice Smith", client.queries.findFirstUser().findUser?.name)
        assertTrue(adapter.getLastCall()!!.variables.isEmpty())
        assertContains(sentQuery(), "findUser(id: \"user-1\")")
    }

    @Test
    fun enumLiteral_isSentInline() = runTest {
        adapter.registerData("listActiveUsers", mapOf("listUsersByStatus" to listOf(kUserAliceJson)))
        assertEquals(1, client.queries.listActiveUsers().listUsersByStatus.size)
        assertTrue(adapter.getLastCall()!!.variables.isEmpty())
        assertContains(sentQuery(), "listUsersByStatus(status: ACTIVE)")
    }

    @Test
    fun severalLiterals_inOneField_areSentInline() = runTest {
        adapter.registerData("searchAlice", mapOf("searchUsers" to listOf(kUserAliceJson)))
        client.queries.searchAlice()
        assertTrue(adapter.getLastCall()!!.variables.isEmpty())
        assertContains(sentQuery(), "searchUsers(name: \"Alice\",limit: 5)")
    }

    @Test
    fun literalAndVariable_canBeMixed() = runTest {
        adapter.registerData("searchWithFixedLimit", mapOf("searchUsers" to listOf(kUserBobJson)))
        client.queries.searchWithFixedLimit("Bob")
        assertEquals(mapOf("name" to "Bob"), adapter.getLastCall()!!.variables)
        assertContains(sentQuery(), "searchUsers(name: \$name,limit: 10)")
    }

    @Test
    fun dollarSigns_insideALiteral_reachTheServerUnchanged() = runTest {
        adapter.registerData("searchPrice", mapOf("searchUsers" to emptyList<Any?>()))
        client.queries.searchPrice()
        assertTrue(adapter.getLastCall()!!.variables.isEmpty())
        assertContains(sentQuery(), "name: \"cost \$5 or \$6\"")
    }
}
