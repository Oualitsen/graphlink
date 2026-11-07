package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.inputs.ClassInput;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.newRealClient;
import static org.junit.jupiter.api.Assertions.assertEquals;

class KeywordTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    @Test
    void keywordQueryAndArgumentRoundTripAgainstTheServer() {
        var res = client.queries.class_("abc");
        assertEquals("abc", res.getClass_().getId());
        assertEquals("class-of-abc", res.getClass_().getClass_());
    }

    @Test
    void keywordInputFieldRoundTripsThroughAMutation() {
        var res = client.mutations.makeClass(new ClassInput("hello"));
        assertEquals("made", res.getMakeClass().getId());
        assertEquals("hello", res.getMakeClass().getClass_());
    }
}
