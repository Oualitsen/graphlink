package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.inputs.*;
import dev.graphlink.test.generated.types.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ExtremeValuesTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    private EverythingEcho echo(EverythingInput input) {
        return client.queries.echoEverything(input).getEchoEverything();
    }

    @Test
    void intAtBoth32BitLimits() {
        EverythingEcho r = echo(EverythingInput.builder().i(2147483647).neg(-2147483648).build());
        assertEquals(2147483647, r.getI());
        assertEquals(-2147483648, r.getNeg());
    }

    @Test
    void floatAt1e308AndNegativeZero() {
        EverythingEcho r = echo(EverythingInput.builder().f(1e308).exp(-0.0).build());
        assertEquals(1e308, r.getF());
        assertEquals(Double.doubleToLongBits(-0.0), Double.doubleToLongBits(r.getExp()));
    }

    @Test
    void aStringWithANulCharacter() {
        assertEquals("a\u0000b", echo(EverythingInput.builder().s("a\u0000b").build()).getS());
    }

    @Test
    void aStringWithLoneSurrogates() {
        String sent = "x\ud800y\udc00z";
        assertEquals(sent, echo(EverythingInput.builder().s(sent).build()).getS());
    }
}
