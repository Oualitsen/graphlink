package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.*
import dev.graphlink.test.generated.interfaces.*
import dev.graphlink.test.generated.types.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.*

@Suppress("UNCHECKED_CAST")
class PolymorphicExtrasTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    private fun names(values: List<Any?>) = values.map { it?.let { v -> v::class.simpleName } }
    private fun map(value: Any?) = value as Map<String, Any?>
    private fun list(value: Any?) = value as List<Any?>

    // ── nested lists of polymorphic types ───────────────────────────────────

    @Test
    fun listsOfListsOfUnionsAndInterfaces() = runBlocking<Unit> {
        val grid = client.queries.grid().grid
        assertEquals(listOf(listOf("Photo", null), listOf("Video"), listOf()), grid.cells.map { names(it!!) })
        assertEquals(listOf(listOf("Article", "Comment"), listOf("Article")), grid.rows.map { names(it) })
        assertEquals(listOf("Photo", "Document"), names(grid.maybe!!.single()!!))
    }

    @Test
    fun emptyAndNullListsStayAsTheyAre() = runBlocking<Unit> {
        val grid = client.queries.grid(true).grid
        assertTrue(grid.cells.isEmpty())
        assertTrue(grid.rows.isEmpty())
        assertNull(grid.maybe)
    }

    @Test
    fun aProjectedSelectionOfNestedLists() = runBlocking<Unit> {
        val grid = client.queries.gridProjected().grid.toJson()
        val cells = list(grid["cells"])
        assertEquals(640, map(list(cells[0])[0])["width"])
        assertNull(list(cells[0])[1])
        assertEquals(30, map(list(cells[1])[0])["seconds"])
        assertTrue(list(cells[2]).isEmpty())
        val rows = list(list(grid["rows"])[0])
        assertEquals("a1", map(rows[0])["id"])
        assertEquals("Hello", map(rows[0])["title"])
        assertEquals("Nice", map(rows[1])["text"])
        val maybe = list(list(grid["maybe"])[0])
        assertEquals("http://cdn/1.png", map(maybe[0])["url"])
        assertEquals("d1", map(maybe[1])["id"])
    }

    // ── custom scalars inside polymorphic types ─────────────────────────────

    @Test
    fun aListOfAUnionWithScalarFields() = runBlocking<Unit> {
        val moments = client.queries.moments().moments
        val stamp = assertIs<Stamp>(moments[0])
        assertEquals("2026-01-02T03:04:05Z", stamp.at)
        assertEquals(4294967296L, stamp.big)
        val span = assertIs<Span>(moments[1])
        assertEquals("2026-02-04", span.until)
        assertEquals("opaque:o-9", span.opaque)
        assertEquals(listOf("2026-03-04T05:06:07Z"), span.dts)
    }

    @Test
    fun aListOfAnInterfaceWithScalarFields() = runBlocking<Unit> {
        val timed = client.queries.timed().timed
        assertEquals(listOf("Span", "Stamp"), names(timed))
        assertEquals("opaque:o-9", assertIs<Span>(timed[0]).opaque)
        assertEquals(4294967296L, assertIs<Stamp>(timed[1]).big)
    }

    @Test
    fun aProjectedUnionKeepsTheScalarsItSelects() = runBlocking<Unit> {
        val moments = client.queries.momentsProjected().moments.map { it.toJson() }
        assertEquals("2026-01-02T03:04:05Z", moments[0]["at"])
        assertEquals(4294967296L, (moments[0]["big"] as Number).toLong())
        assertEquals("o-9", moments[1]["opaque"])
        assertEquals("2026-02-04", moments[1]["until"])
    }

    @Test
    fun anInterfaceSelectionSharesTheInterfaceScalar() = runBlocking<Unit> {
        val timed = client.queries.timedProjected().timed.map { it.toJson() }
        assertEquals(listOf("2026-02-03T04:05:06Z", "2026-01-02T03:04:05Z"), timed.map { it["at"] })
        assertEquals("o-9", timed[0]["opaque"])
        assertEquals(4294967296L, (timed[1]["big"] as Number).toLong())
    }

    // ── a union member that points back at its union ────────────────────────

    @Test
    fun aChainThreeLevelsDeep() = runBlocking<Unit> {
        val chain = client.queries.chainDeep("l1").chain!!.toJson()
        assertEquals("l1", chain["id"])
        assertEquals("l2", map(chain["next"])["id"])
        assertEquals("e1", map(map(chain["next"])["next"])["id"])
        assertEquals("done", map(map(chain["next"])["next"])["reason"])
    }

    @Test
    fun theEndOfTheChainDirectlyAndAnUnknownId() = runBlocking<Unit> {
        assertEquals("done", client.queries.chainDeep("e1").chain!!.toJson()["reason"])
        assertNull(client.queries.chainDeep("nope").chain)
    }

    @Test
    fun theAllFieldsSelectionStopsAfterOneLevel() = runBlocking<Unit> {
        val chain = client.queries.chain("l1").chain!!.toJson()
        assertEquals("l1", chain["id"])
        assertEquals("l2", map(chain["next"])["id"])
    }

    // ── lists of unions and interfaces in every operation kind ──────────────

    private suspend fun cachedVideoSeconds() = assertIs<Video>(client.queries.cachedAttachments().cachedAttachments[1]).seconds

    @Test
    fun aCachedListIsServedOnceAndFetchedAgainAfterItsTagIsEvicted() = runBlocking<Unit> {
        assertEquals(listOf("Photo", "Video", "Document"), names(client.queries.cachedAttachments().cachedAttachments))
        val before = cachedVideoSeconds()
        assertEquals(before, cachedVideoSeconds())
        client.mutations.evictAttachments()
        assertNotEquals(before, cachedVideoSeconds())
    }

    @Test
    fun anErrorOnAListOfUnionsThrowsAndAGoodCallStillWorks() = runBlocking<Unit> {
        assertFails { client.queries.failingAttachments(true) }
        assertEquals(3, client.queries.failingAttachments(false).failingAttachments.size)
    }

    @Test
    fun aMutationReturningAListOfUnions() = runBlocking<Unit> {
        assertEquals(
            listOf("Photo", "Video", "Document", "Photo", "Video"),
            names(client.mutations.bulkAttachments(5).bulkAttachments))
        assertTrue(client.mutations.bulkAttachments(0).bulkAttachments.isEmpty())
    }

    @Test
    fun aMutationReturningAListOfAnInterface() = runBlocking<Unit> {
        assertEquals(listOf("Article", "Comment", "Article"), names(client.mutations.bulkEntities().bulkEntities))
    }

    private suspend fun <T> streaming(block: suspend (GraphLinkClient) -> T): T {
        val ws = dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter(Fixtures.WS_URL)
        try {
            val codec = dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec()
            return withTimeout(10_000) { block(GraphLinkClient(OkHttpGraphLinkClientAdapter(Fixtures.SERVER_URL), ws, MockMultipartAdapter(), codec, codec)) }
        } finally {
            ws.close()
        }
    }

    @Test
    fun aSubscriptionEmittingListsOfUnions() = runBlocking<Unit> {
        val batches = streaming { it.subscriptions.attachmentsBatch().take(2).toList() }
        assertEquals(listOf("Photo", "Video", "Document"), names(batches[0].attachmentsBatch))
        assertEquals(listOf("Document"), names(batches[1].attachmentsBatch))
    }

    @Test
    fun aSubscriptionEmittingAListOfAnInterface() = runBlocking<Unit> {
        val batch = streaming { it.subscriptions.entityBatch().first() }
        assertEquals(listOf("Article", "Comment"), names(batch.entityBatch))
    }

    // ── @oneOf inputs with richer members ───────────────────────────────────

    private suspend fun pick(pick: Pick) = client.queries.describePick(pick).describePick

    @Test
    fun oneOfWithAnInputObject() = runBlocking<Unit> {
        assertEquals("{inner={label=x, n=5, tags=[t]}}", pick(Pick(inner = InnerInput(5, "x", listOf("t")))))
    }

    @Test
    fun oneOfWithAnEnum() = runBlocking<Unit> {
        assertEquals("{status=SUSPENDED}", pick(Pick(status = UserStatus.SUSPENDED)))
    }

    @Test
    fun oneOfWithAListIncludingAnEmptyOne() = runBlocking<Unit> {
        assertEquals("{ids=[1, 2]}", pick(Pick(ids = listOf(1, 2))))
        assertEquals("{ids=[]}", pick(Pick(ids = listOf())))
    }

    @Test
    fun oneOfWithAnotherOneOf() = runBlocking<Unit> {
        assertEquals("{pet={cat=Tom}}", pick(Pick(pet = Pet(cat = "Tom"))))
    }

    @Test
    fun oneOfNestedInItself() = runBlocking<Unit> {
        assertEquals("{child={child={pet={dog=3}}}}", pick(Pick(child = Pick(child = Pick(pet = Pet(dog = 3))))))
    }

    @Test
    fun aListOfOneOfInputsInsideARegularInput() = runBlocking<Unit> {
        val pets = listOf(Pet(cat = "a"), Pet(dog = 2))
        assertEquals("{lead={dog=3}, pets=[{cat=a}, {dog=2}]}", client.queries.describeBasket(Basket(pets, Pet(dog = 3))).describeBasket)
        assertEquals("{pets=[{cat=a}, {dog=2}]}", client.queries.describeBasket(Basket(pets)).describeBasket)
        assertEquals("{pets=[]}", client.queries.describeBasket(Basket(listOf())).describeBasket)
    }
}
