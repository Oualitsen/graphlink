package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class GlHashTest {
    private final GraphLinkClient client = Helpers.newClient(new ApqServer());

    @Test
    void hashesAQueryLikeAReferenceSha256() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", client.queries.glHash("abc"));
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", client.queries.glHash(""));
    }

    @Test
    void hashesARealGraphQLDocument() {
        assertEquals("76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc",
                client.queries.glHash("query GetUser($id: ID!){getUser(id:$id){id name}}"));
    }

    @Test
    void isTheSameForRepeatedCalls() {
        String first = client.queries.glHash("query A{a}");
        assertEquals(first, client.queries.glHash("query A{a}"));
        assertNotEquals(first, client.queries.glHash("query B{b}"));
    }

    @Test
    void isSharedByQueriesAndMutationsThroughTheBaseClass() {
        assertEquals(client.queries.glHash("abc"), client.mutations.glHash("abc"));
    }
}
