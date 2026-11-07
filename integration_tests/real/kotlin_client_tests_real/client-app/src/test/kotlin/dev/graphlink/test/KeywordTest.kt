package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.inputs.ClassInput
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class KeywordTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun keywordQueryAndArgumentRoundTripAgainstTheServer() = runTest {
        val res = client.queries.class_("abc")
        assertEquals("abc", res.class_.id)
        assertEquals("class-of-abc", res.class_.class_)
    }

    @Test
    fun keywordInputFieldRoundTripsThroughAMutation() = runTest {
        val res = client.mutations.makeClass(ClassInput(class_ = "hello"))
        assertEquals("made", res.makeClass.id)
        assertEquals("hello", res.makeClass.class_)
    }
}
