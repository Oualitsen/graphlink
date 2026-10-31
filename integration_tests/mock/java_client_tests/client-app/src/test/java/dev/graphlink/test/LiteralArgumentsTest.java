package dev.graphlink.test;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class LiteralArgumentsTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    private String sentQuery() throws Exception {
        Map<?, ?> payload = new ObjectMapper().readValue(adapter.getLastCall().rawPayload(), Map.class);
        return (String) payload.get("query");
    }

    @Test
    void stringLiteral_isSentInline_andNeedsNoParameter() throws Exception {
        adapter.registerData("findFirstUser", Map.of("findUser", kUserAliceJson));
        assertEquals("Alice Smith", client.queries.findFirstUser().getFindUser().getName());
        assertTrue(adapter.getLastCall().variables().isEmpty());
        assertTrue(sentQuery().contains("findUser(id: \"user-1\")"));
    }

    @Test
    void enumLiteral_isSentInline() throws Exception {
        adapter.registerData("listActiveUsers", Map.of("listUsersByStatus", List.of(kUserAliceJson)));
        assertEquals(1, client.queries.listActiveUsers().getListUsersByStatus().size());
        assertTrue(adapter.getLastCall().variables().isEmpty());
        assertTrue(sentQuery().contains("listUsersByStatus(status: ACTIVE)"));
    }

    @Test
    void severalLiterals_inOneField_areSentInline() throws Exception {
        adapter.registerData("searchAlice", Map.of("searchUsers", List.of(kUserAliceJson)));
        client.queries.searchAlice();
        assertTrue(adapter.getLastCall().variables().isEmpty());
        assertTrue(sentQuery().contains("searchUsers(name: \"Alice\",limit: 5)"));
    }

    @Test
    void literalAndVariable_canBeMixed() throws Exception {
        adapter.registerData("searchWithFixedLimit", Map.of("searchUsers", List.of(kUserBobJson)));
        client.queries.searchWithFixedLimit("Bob");
        assertEquals(Map.of("name", "Bob"), adapter.getLastCall().variables());
        assertTrue(sentQuery().contains("searchUsers(name: $name,limit: 10)"));
    }

    @Test
    void dollarSigns_insideALiteral_reachTheServerUnchanged() throws Exception {
        adapter.registerData("searchPrice", Map.of("searchUsers", List.of()));
        client.queries.searchPrice();
        assertTrue(adapter.getLastCall().variables().isEmpty());
        assertTrue(sentQuery().contains("name: \"cost $5 or $6\""));
    }
}
