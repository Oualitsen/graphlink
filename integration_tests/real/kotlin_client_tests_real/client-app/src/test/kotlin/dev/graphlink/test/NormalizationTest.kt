package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.EventType
import dev.graphlink.test.generated.inputs.NormalizedInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.newRealClient

/**
 * End-to-end coverage for identifier normalization.
 *
 * Schema uses non-canonical field casing:
 *   - FirstName  → Kotlin codeName: firstName
 *   - last_name  → Kotlin codeName: lastName
 *   - USER_AGE   → Kotlin codeName: userAge
 *   - event_type → Kotlin codeName: eventType
 *
 * Enum values use SCREAMING_SNAKE_CASE in Kotlin (wire: pending → PENDING,
 * in_progress → IN_PROGRESS, completed_ok → COMPLETED_OK). Wire names are
 * always used in the GraphQL request and toJson/fromJson.
 */
class NormalizationTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── EventType enum round-trip ─────────────────────────────────────────────

    @Nested
    inner class EventTypeRoundTrip {

        @Test
        fun pending_roundTrips() {
            assertEquals("pending", EventType.PENDING.toJson())
            assertEquals(EventType.PENDING, EventType.fromJson("pending"))
        }

        @Test
        fun inProgress_roundTrips() {
            assertEquals("in_progress", EventType.IN_PROGRESS.toJson())
            assertEquals(EventType.IN_PROGRESS, EventType.fromJson("in_progress"))
        }

        @Test
        fun completedOk_roundTrips() {
            assertEquals("completed_ok", EventType.COMPLETED_OK.toJson())
            assertEquals(EventType.COMPLETED_OK, EventType.fromJson("completed_ok"))
        }


    }

    // ── Field normalization — getNormalizedRecord ─────────────────────────────

    @Nested
    inner class FieldNormalization {

        @Test
        fun firstName_isAccessible_wireNameFirstName() = runTest {
            val res = client.queries.getNormalizedRecord("rec-1")
            assertEquals("Alice", res.getNormalizedRecord.firstName)
        }

        @Test
        fun lastName_isAccessible_wireNameLastName() = runTest {
            val res = client.queries.getNormalizedRecord("rec-1")
            assertEquals("Smith", res.getNormalizedRecord.lastName)
        }

        @Test
        fun userAge_isAccessible_wireNameUSER_AGE() = runTest {
            val res = client.queries.getNormalizedRecord("rec-1")
            assertEquals(30, res.getNormalizedRecord.userAge)
        }

        @Test
        fun eventType_isScreamingSnake_wireNameIn_progress() = runTest {
            val res = client.queries.getNormalizedRecord("rec-1")
            assertEquals(EventType.IN_PROGRESS, res.getNormalizedRecord.eventType)
        }
    }

    // ── Input normalization — createNormalizedRecord ──────────────────────────

    @Nested
    inner class InputNormalization {

        @Test
        fun normalizedInputFields_roundTripThroughServer() = runTest {
            val input = NormalizedInput(
                firstName = "Bob",
                lastName = "Jones",
                eventType = EventType.COMPLETED_OK,
            )
            val res = client.mutations.createNormalizedRecord(input)
            assertEquals("Bob", res.createNormalizedRecord.firstName)
            assertEquals("Jones", res.createNormalizedRecord.lastName)
            assertEquals(EventType.COMPLETED_OK, res.createNormalizedRecord.eventType)
        }
    }
}
