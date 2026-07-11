package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.enums.Priority;
import dev.graphlink.server.generated.inputs.ConfigInput;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

public class DefaultsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Test
    void inputFieldDefaultsAppliedWhenOmitted() {
        var c = client.queries.resolveConfig(ConfigInput.builder().build()).getResolveConfig();
        assertEquals(25, c.getPageSize());
        assertEquals(1.5, c.getRatio());
        assertEquals("asc", c.getSort());
        assertFalse(c.getVerbose());
        assertEquals(Priority.MEDIUM, c.getPriority());
        assertEquals(List.of("default", "seed"), c.getTags());
        assertTrue(c.getEmpties().isEmpty());
        assertNull(c.getNote());
    }

    @Test
    void explicitValuesOverrideDefaults() {
        var c = client.queries.resolveConfig(ConfigInput.builder()
                .pageSize(5).sort("desc").priority(Priority.HIGH).note("x").build()).getResolveConfig();
        assertEquals(5, c.getPageSize());
        assertEquals("desc", c.getSort());
        assertEquals(Priority.HIGH, c.getPriority());
        assertEquals("x", c.getNote());
    }

    @Test
    void nestedObjectArgDefaultMergesWithFieldDefaults() {
        var range = client.queries.resolveRange(null).getResolveRange();
        assertEquals(5, range.getMin());
        assertEquals(100, range.getMax());
    }

    @Test
    void argumentLevelScalarDefaults() {
        assertEquals("Hi world!", client.queries.greet(null, null).getGreet());
        assertEquals("Hi Bob!Hi Bob!", client.queries.greet("Bob", 2).getGreet());
    }

    @Test
    void enumArgumentPassedValueRoundTripsOmittedUsesDefaultHigh() {
        assertEquals(Priority.LOW, client.queries.echoPriority(Priority.LOW).getEchoPriority());
        assertEquals(Priority.HIGH, client.queries.echoPriority(null).getEchoPriority());
    }
}
