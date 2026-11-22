package dev.graphlink.errors;

import dev.graphlink.errors.generated.client.GraphLinkClient;
import dev.graphlink.errors.generated.client.GraphLinkDomainError;
import dev.graphlink.errors.generated.client.RestError;
import dev.graphlink.errors.generated.errors.ItemConflict;
import dev.graphlink.errors.generated.errors.ItemNotFound;
import dev.graphlink.errors.generated.errors.RateLimited;
import dev.graphlink.errors.generated.errors.Teapot;
import dev.graphlink.errors.generated.inputs.ItemInput;
import org.junit.jupiter.api.Test;

import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.*;

class RestErrorsTest {

    private final GraphLinkClient client = new GraphLinkClient("http://127.0.0.1:9930/graphql", "http://127.0.0.1:9930");

    private static RuntimeException thrownBy(Supplier<Object> call) {
        try {
            call.get();
        } catch (RuntimeException e) {
            return e;
        }
        return fail("expected an exception");
    }

    @Test
    void aSuccessfulCallReturnsItsData() {
        assertEquals("Item 1", Rx.block(client.queries.item("1")).getName());
    }

    @Test
    void aStatusOnlyErrorIsThrownWithTheFieldsOfTheBody() {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.item("missing")));
        assertTrue(e instanceof ItemNotFound);
        assertTrue(e instanceof GraphLinkDomainError);
        assertEquals("missing", ((ItemNotFound) e).getId());
        assertEquals("Item missing not found", e.getMessage());
    }

    @Test
    void itCanBeCaughtByType() {
        String caught = "";
        try {
            Rx.block(client.queries.item("conflict"));
        } catch (ItemConflict e) {
            caught = e.getReason();
        }
        assertEquals("duplicate", caught);
    }

    @Test
    void aStatusWithItsOwnValueMatchesTheBodyCode() {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.item("conflict")));
        assertTrue(e instanceof ItemConflict);
        assertEquals("Conflict", e.getMessage());
    }

    @Test
    void aCustomFieldPathIsReadFromTheBody() {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.item("rate")));
        assertTrue(e instanceof RateLimited);
        assertEquals(30, ((RateLimited) e).getRetryAfter());
    }

    @Test
    void aStatusOnlyErrorDoesNotNeedAJsonBody() {
        assertTrue(thrownBy(() -> Rx.block(client.queries.item("teapot"))) instanceof Teapot);
    }

    @Test
    void aStatusOnlyErrorWithAnHtmlBodyStillMatchesByStatus() {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.item("html-404")));
        assertTrue(e instanceof ItemNotFound);
        assertNull(((ItemNotFound) e).getId());
    }

    @Test
    void aMutationThrowsItsDeclaredError() {
        RuntimeException e = thrownBy(() -> Rx.block(client.mutations.createItem(new ItemInput("dup"))));
        assertTrue(e instanceof ItemConflict);
        assertEquals("name taken", ((ItemConflict) e).getReason());
    }

    @Test
    void aMutationReturnsItsData() {
        assertEquals("new", Rx.block(client.mutations.createItem(new ItemInput("fresh"))).getId());
    }

    private void fallsBack(String id, int status) {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.item(id)));
        assertTrue(e instanceof RestError, id + " -> " + e);
        assertFalse(e instanceof GraphLinkDomainError);
        assertEquals(status, ((RestError) e).getStatus());
    }

    @Test
    void aBodyMissingARequiredFieldKeepsRestError() { fallsBack("conflict-no-reason", 409); }

    @Test
    void aCodeTheClientDoesNotKnowKeepsRestError() { fallsBack("conflict-other", 409); }

    @Test
    void aMistypedFieldKeepsRestError() { fallsBack("rate-bad", 429); }

    @Test
    void aProxyErrorWithAnHtmlBodyKeepsRestError() { fallsBack("bad-gateway", 502); }

    @Test
    void anOperationWithoutThrowsKeepsRestError() {
        RuntimeException e = thrownBy(() -> Rx.block(client.queries.itemPlain("x")));
        assertTrue(e instanceof RestError);
        assertEquals(404, ((RestError) e).getStatus());
    }
}
