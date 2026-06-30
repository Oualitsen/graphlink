package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.EventType;
import dev.graphlink.test.generated.inputs.NormalizedInput;
import dev.graphlink.test.generated.types.CreateNormalizedRecordResponse;
import dev.graphlink.test.generated.types.GetNormalizedRecordResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

/**
 * End-to-end coverage for identifier normalization.
 *
 * Schema uses non-canonical field casing:
 *   - FirstName  → Java codeName: getFirstName()
 *   - last_name  → Java codeName: getLastName()
 *   - USER_AGE   → Java codeName: getUserAge()
 *   - event_type → Java codeName: getEventType()
 *
 * Enum values use SCREAMING_SNAKE_CASE in Java (wire: pending → PENDING,
 * in_progress → IN_PROGRESS, completed_ok → COMPLETED_OK). Wire names are
 * always used in toJson/fromJson and the GraphQL request body.
 */
class NormalizationTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── EventType enum round-trip ─────────────────────────────────────────────

    @Nested
    class EventTypeRoundTrip {

        @Test
        void pending_roundTrips() {
            assertEquals("pending", EventType.PENDING.toJson());
            assertEquals(EventType.PENDING, EventType.fromJson("pending"));
        }

        @Test
        void inProgress_roundTrips() {
            assertEquals("in_progress", EventType.IN_PROGRESS.toJson());
            assertEquals(EventType.IN_PROGRESS, EventType.fromJson("in_progress"));
        }

        @Test
        void completedOk_roundTrips() {
            assertEquals("completed_ok", EventType.COMPLETED_OK.toJson());
            assertEquals(EventType.COMPLETED_OK, EventType.fromJson("completed_ok"));
        }

        @Test
        void fromJson_null_returnsNull() {
            assertNull(EventType.fromJson(null));
        }
    }

    // ── Field normalization — getNormalizedRecord ─────────────────────────────

    @Nested
    class FieldNormalization {

        @Test
        void firstName_isAccessible_wireNameFirstName() {
            GetNormalizedRecordResponse res = client.queries.getNormalizedRecord("rec-1");
            assertEquals("Alice", res.getGetNormalizedRecord().getFirstName());
        }

        @Test
        void lastName_isAccessible_wireNameLastName() {
            GetNormalizedRecordResponse res = client.queries.getNormalizedRecord("rec-1");
            assertEquals("Smith", res.getGetNormalizedRecord().getLastName());
        }

        @Test
        void userAge_isAccessible_wireNameUSER_AGE() {
            GetNormalizedRecordResponse res = client.queries.getNormalizedRecord("rec-1");
            assertEquals(30, res.getGetNormalizedRecord().getUserAge());
        }

        @Test
        void eventType_isScreamingSnake_wireNameIn_progress() {
            GetNormalizedRecordResponse res = client.queries.getNormalizedRecord("rec-1");
            assertEquals(EventType.IN_PROGRESS, res.getGetNormalizedRecord().getEventType());
        }
    }

    // ── Input normalization — createNormalizedRecord ──────────────────────────

    @Nested
    class InputNormalization {

        @Test
        void normalizedInputFields_roundTripThroughServer() {
            NormalizedInput input = NormalizedInput.builder()
                    .firstName("Bob")
                    .lastName("Jones")
                    .eventType(EventType.COMPLETED_OK)
                    .build();
            CreateNormalizedRecordResponse res = client.mutations.createNormalizedRecord(input);
            assertEquals("Bob", res.getCreateNormalizedRecord().getFirstName());
            assertEquals("Jones", res.getCreateNormalizedRecord().getLastName());
            assertEquals(EventType.COMPLETED_OK, res.getCreateNormalizedRecord().getEventType());
        }
    }
}
