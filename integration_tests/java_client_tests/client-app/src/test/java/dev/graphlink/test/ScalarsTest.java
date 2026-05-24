package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.GetAllScalarsResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class ScalarsTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── Non-nullable scalar fields ────────────────────────────────────────────

    @Nested
    class NonNullableScalarFields {

        @BeforeEach
        void register() {
            adapter.registerData("getAllScalars", Map.of("getAllScalars", kAllScalarsNullJson));
        }

        @Test
        void id_deserializesToString() {
            GetAllScalarsResponse res = client.queries.getAllScalars("scalar-1");
            assertInstanceOf(String.class, res.getGetAllScalars().getId());
            assertEquals("scalar-1", res.getGetAllScalars().getId());
        }

        @Test
        void strVal_deserializesToString() {
            GetAllScalarsResponse res = client.queries.getAllScalars("scalar-1");
            assertInstanceOf(String.class, res.getGetAllScalars().getStrVal());
            assertEquals("hello world", res.getGetAllScalars().getStrVal());
        }

        @Test
        void intVal_deserializesToInteger() {
            GetAllScalarsResponse res = client.queries.getAllScalars("scalar-1");
            assertInstanceOf(Integer.class, res.getGetAllScalars().getIntVal());
            assertEquals(42, res.getGetAllScalars().getIntVal());
        }

        @Test
        void floatVal_deserializesToDouble() {
            GetAllScalarsResponse res = client.queries.getAllScalars("scalar-1");
            assertInstanceOf(Double.class, res.getGetAllScalars().getFloatVal());
            assertEquals(3.14, res.getGetAllScalars().getFloatVal(), 0.001);
        }

        @Test
        void boolVal_deserializesToBoolean() {
            GetAllScalarsResponse res = client.queries.getAllScalars("scalar-1");
            assertInstanceOf(Boolean.class, res.getGetAllScalars().getBoolVal());
            assertTrue(res.getGetAllScalars().getBoolVal());
        }
    }

    // ── Nullable scalar fields — null in response ─────────────────────────────

    @Nested
    class NullableScalarFields_Null {

        @BeforeEach
        void register() {
            adapter.registerData("getAllScalars", Map.of("getAllScalars", kAllScalarsNullJson));
        }

        @Test
        void nullableStr_isNull() {
            assertNull(client.queries.getAllScalars("scalar-1").getGetAllScalars().getNullableStr());
        }

        @Test
        void nullableInt_isNull() {
            assertNull(client.queries.getAllScalars("scalar-1").getGetAllScalars().getNullableInt());
        }

        @Test
        void nullableFloat_isNull() {
            assertNull(client.queries.getAllScalars("scalar-1").getGetAllScalars().getNullableFloat());
        }

        @Test
        void nullableBool_isNull() {
            assertNull(client.queries.getAllScalars("scalar-1").getGetAllScalars().getNullableBool());
        }

        @Test
        void nullableId_isNull() {
            assertNull(client.queries.getAllScalars("scalar-1").getGetAllScalars().getNullableId());
        }
    }

    // ── Nullable scalar fields — values present ───────────────────────────────

    @Nested
    class NullableScalarFields_Present {

        @BeforeEach
        void register() {
            adapter.registerData("getAllScalars", Map.of("getAllScalars", kAllScalarsPresentJson));
        }

        @Test
        void nullableStr_hasValue() {
            assertEquals("present", client.queries.getAllScalars("scalar-2").getGetAllScalars().getNullableStr());
        }

        @Test
        void nullableInt_hasValue() {
            assertEquals(99, client.queries.getAllScalars("scalar-2").getGetAllScalars().getNullableInt());
        }

        @Test
        void nullableFloat_hasValue() {
            assertEquals(2.718, client.queries.getAllScalars("scalar-2").getGetAllScalars().getNullableFloat(), 0.001);
        }

        @Test
        void nullableBool_isFalse_notNull() {
            Boolean val = client.queries.getAllScalars("scalar-2").getGetAllScalars().getNullableBool();
            assertNotNull(val);
            assertFalse(val);
        }

        @Test
        void negativeInt_deserializesCorrectly() {
            assertEquals(-1, client.queries.getAllScalars("scalar-2").getGetAllScalars().getIntVal());
        }

        @Test
        void negativeFloat_deserializesCorrectly() {
            assertEquals(-0.5, client.queries.getAllScalars("scalar-2").getGetAllScalars().getFloatVal(), 0.001);
        }

        @Test
        void boolFalse_isNotTreatedAsNull() {
            Boolean val = client.queries.getAllScalars("scalar-2").getGetAllScalars().getBoolVal();
            assertNotNull(val);
            assertFalse(val);
        }
    }

    // ── Outgoing request shape ────────────────────────────────────────────────

    @Nested
    class OutgoingRequestShape {

        @BeforeEach
        void register() {
            adapter.registerData("getAllScalars", Map.of("getAllScalars", kAllScalarsNullJson));
        }

        @Test
        void idArgument_isSentAsStringInVariables() {
            client.queries.getAllScalars("scalar-1");
            assertEquals("scalar-1", adapter.getLastCall().variables().get("id"));
        }

        @Test
        void operationName_isGetAllScalars() {
            client.queries.getAllScalars("scalar-1");
            assertEquals("getAllScalars", adapter.getLastCall().operationName());
        }
    }
}
