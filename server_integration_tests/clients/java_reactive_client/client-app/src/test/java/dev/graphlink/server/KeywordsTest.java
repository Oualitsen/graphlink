package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.enums.Keyword;
import dev.graphlink.server.generated.inputs.ReservedInput;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

public class KeywordsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Test
    void reservedWordFieldsRoundTripBothJavaOnly() {
        var r = client.queries.reserved().block().getReserved();
        assertEquals("cls", r.getClass_());
        assertEquals(42, r.getReturn_());
        assertTrue(r.getNew_());
        assertEquals("def", r.getDefault_());
        assertEquals("yes", r.getIs());
        assertEquals("inside", r.getIn());
        assertEquals("w", r.getWith());
        assertEquals(7, r.getInt_());
        assertFalse(r.getSynchronized_());
        assertEquals("n", r.getNative_());
        assertEquals(Keyword.CLASS, r.getKind());
        assertEquals("v", r.getNested().getValue());
        assertEquals("tok", r.getSecret().getToken());
    }

    @Test
    void reservedOperationNamePlusReservedArgumentNames() {
        var res = client.queries.switch_("x", 5).block();
        assertEquals("x", res.getSwitch_().getClass_());
        assertEquals(5, res.getSwitch_().getReturn_());
    }

    @Test
    void leadingUnderscoreOperation() {
        var res = client.queries.status().block();
        assertEquals("ok", res.getStatus());
    }

    @Test
    void collidingFieldNamesStayDistinct() {
        var c = client.queries.collide().block().getCollide();
        assertTrue(List.of(c.getClass_2(), c.getClass2()).containsAll(List.of("A", "B")));
    }

    @Test
    void reservedWordInputFieldsMutation() {
        var res = client.mutations.echoReserved(
                ReservedInput.builder()
                        .class_("X").return_(5).default_("D").is(true).synchronized_(3).build()).block();
        assertEquals("X", res.getEchoReserved().getClass_());
        assertEquals(5, res.getEchoReserved().getReturn_());
        assertEquals("D", res.getEchoReserved().getDefault_());
    }
}
