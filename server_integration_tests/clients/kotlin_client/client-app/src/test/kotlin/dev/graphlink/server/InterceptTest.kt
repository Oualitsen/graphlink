package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.client.GraphLinkException
import dev.graphlink.server.generated.inputs.ListTeamsFieldArgs
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.time.Duration.Companion.seconds

class InterceptTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun greetInterceptedAppendsTheRunBeforeMarkerToTheNameArgument() = runTest {
        val res = client.queries.greetIntercepted("Ada")
        assertEquals("Hello, Ada(runBefore)", res.greetIntercepted.message)
    }

    @Test
    fun greetPlainIsNotInterceptedNoMarkerAppended() = runTest {
        val res = client.queries.greetPlain("Ada")
        assertEquals("Hello, Ada", res.greetPlain.message)
    }

    @Test
    fun greetingReceivedBakesTheMarkerIntoEveryEmittedGreeting() = runBlocking {
        val eventDeferred = async {
            withTimeout(10.seconds) {
                client.subscriptions.greetingReceived().first()
            }
        }

        delay(300)

        client.mutations.sendGreeting("Ada")

        val event = eventDeferred.await()
        assertEquals("Hello, Ada(runBefore)", event.greetingReceived.message)
    }

    @Test
    fun teamMembersInterceptedMappingAllowsRoleAuth() = runTest {
        val res = client.queries.listTeams(ListTeamsFieldArgs(membersRole = "auth"))
        val members = res.listTeams.first().members.map { it.name }.toSet()
        assertEquals(setOf("Ada", "Grace"), members)
    }

    @Test
    fun teamMembersInterceptedMappingDeniesAnyOtherRole() = runTest {
        assertFailsWith<GraphLinkException> {
            client.queries.listTeams(ListTeamsFieldArgs(membersRole = "wrong"))
        }
    }
}
