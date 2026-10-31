package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class LiteralArgumentsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    @Test
    void stringLiteral_selectsTheRightUser() {
        var user = client.queries.findFirstUser().getFindUser();
        assertEquals("Alice Smith", user.getName());
        assertEquals("alice@test.com", user.getEmail());
    }

    @Test
    void enumLiteral_filtersOnTheServer() {
        var users = client.queries.listActiveUsers().getListUsersByStatus();
        assertEquals(1, users.size());
        assertEquals("user-1", users.get(0).getId());
    }

    @Test
    void severalLiterals_inOneField_areApplied() {
        var users = client.queries.searchAlice().getSearchUsers();
        assertEquals(1, users.size());
        assertEquals("Alice Smith", users.get(0).getName());
    }

    @Test
    void inlineLimit_isEnforced_whileTheOtherArgumentStaysAVariable() {
        assertEquals(1, client.queries.searchWithFixedLimit("s").getSearchUsers().size());
    }

    @Test
    void dollarSigns_insideALiteral_formAValidQuery() {
        assertTrue(client.queries.searchPrice().getSearchUsers().isEmpty());
    }
}
