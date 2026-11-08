package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.inputs.ScalarsInput;
import dev.graphlink.test.generated.types.ScalarBag;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static dev.graphlink.test.Fixtures.newRealClient;
import static org.junit.jupiter.api.Assertions.*;

class ScalarCodecTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    @Test
    void codecScalarIsDecodedInAResponse() {
        assertEquals("opaque:o-1", client.queries.scalarFixture().getScalarFixture().getOpaque());
    }

    @Test
    void codecScalarIsEncodedInAnInputFieldAndDecodedAgain() {
        ScalarsInput input = new ScalarsInput("x", null, 1L, null, null, "opaque:xyz", List.of(), null);
        assertEquals("opaque:xyz", client.queries.echoScalars(input).getEchoScalars().getOpaque());
    }

    @Test
    void codecScalarIsEncodedInAnOperationArgumentAndDecodedAgain() {
        ScalarBag bag = client.queries.echoScalarArgs("x", null, 1L, null, null, "opaque:abc", List.of(), null).getEchoScalarArgs();
        assertEquals("opaque:abc", bag.getOpaque());
    }

    @Test
    void codecScalarKeepsNullAsNull() {
        assertNull(client.queries.echoScalarArgs("x", null, 1L, null, null, null, List.of(), null).getEchoScalarArgs().getOpaque());
        assertNull(client.queries.echoScalars(new ScalarsInput("x", null, 1L, null, null, null, List.of(), null)).getEchoScalars().getOpaque());
    }

    @Test
    void aliasScalarsKeepLongPrecisionAndJsonShape() {
        ScalarBag bag = client.queries.scalarFixture().getScalarFixture();
        assertEquals(9007199254740993L, bag.getLong_());
        assertEquals(Arrays.asList(1L, null, 9223372036854775807L), bag.getLongs());
        assertEquals("2026-01-02T03:04:05Z", bag.getDt());
        assertEquals("x", ((java.util.Map<?, ?>) bag.getJson()).get("name"));
    }

    private GraphLinkClient fixtureClient(String opaque) {
        MockAdapter adapter = new MockAdapter();
        adapter.register("scalarFixture", "{\"data\":{\"scalarFixture\":{\"dt\":\"x\",\"long\":1,\"dts\":[],\"opaque\":" + opaque + "}}}");
        return Fixtures.newClient(adapter, new MockWebSocketAdapter());
    }

    @Test
    void codecScalarOfTheWrongTypeFailsInsteadOfBeingCastBlindly() {
        for (String wire : List.of("7", "true", "1.5", "{\"a\":1}", "[\"a\"]")) {
            assertThrows(RuntimeException.class, () -> fixtureClient(wire).queries.scalarFixture(), wire);
        }
    }

    @Test
    void codecScalarOfTheRightTypeStillRunsTheTemplate() {
        assertEquals("opaque:abc", fixtureClient("\"abc\"").queries.scalarFixture().getScalarFixture().getOpaque());
    }
}
