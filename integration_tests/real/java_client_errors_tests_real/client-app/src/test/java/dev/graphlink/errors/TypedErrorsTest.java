package dev.graphlink.errors;

import dev.graphlink.errors.generated.client.GraphLinkClient;
import dev.graphlink.errors.generated.client.GraphLinkDomainError;
import dev.graphlink.errors.generated.client.GraphLinkException;
import dev.graphlink.errors.generated.enums.Reason;
import dev.graphlink.errors.generated.errors.ArticleNotFound;
import dev.graphlink.errors.generated.errors.Banned;
import dev.graphlink.errors.generated.errors.Forbidden;
import dev.graphlink.errors.generated.errors.TitleTaken;
import dev.graphlink.errors.generated.inputs.ArticleInput;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.*;

class TypedErrorsTest {

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
        assertEquals("1", client.queries.article("1").getArticle().getId());
    }

    @Test
    void aDeclaredErrorIsThrownAsItsClassWithItsFields() {
        RuntimeException e = thrownBy(() -> client.queries.article("missing"));
        assertTrue(e instanceof ArticleNotFound);
        assertTrue(e instanceof GraphLinkDomainError);
        assertEquals("missing", ((ArticleNotFound) e).getId());
        assertEquals("Article missing not found", e.getMessage());
    }

    @Test
    void itCanBeCaughtByType() {
        String caught = "";
        try {
            client.queries.article("missing");
        } catch (ArticleNotFound e) {
            caught = e.getId();
        }
        assertEquals("missing", caught);
    }

    @Test
    void anErrorMatchedOnACustomFieldAndValue() {
        RuntimeException e = thrownBy(() -> client.queries.article("forbidden"));
        assertTrue(e instanceof Forbidden);
        assertEquals("No access", e.getMessage());
    }

    @Test
    void anErrorOfAnotherRootField() {
        assertTrue(thrownBy(() -> client.queries.secret()) instanceof Forbidden);
    }

    @Test
    void fallbacksKeepTheException() {
        for (String id : Arrays.asList("other-code", "no-field", "no-path", "no-extensions")) {
            RuntimeException e = thrownBy(() -> client.queries.article(id));
            assertTrue(e instanceof GraphLinkException, id);
            assertFalse(e instanceof GraphLinkDomainError, id);
        }
    }

    @Test
    void anUnknownCodeKeepsItsMessage() {
        GraphLinkException e = (GraphLinkException) thrownBy(() -> client.queries.article("other-code"));
        assertEquals("A new error", e.getErrors().get(0).getMessage());
    }

    @Test
    void anOperationWithoutThrowsKeepsTheException() {
        RuntimeException e = thrownBy(() -> client.queries.plain("1"));
        assertTrue(e instanceof GraphLinkException);
        assertFalse(e instanceof GraphLinkDomainError);
    }

    @Test
    void aCombinedQueryKeepsTheException() {
        GraphLinkException e = (GraphLinkException) thrownBy(() -> client.queries.pair());
        assertEquals(Arrays.<Object>asList("first"), e.getErrors().get(0).getPath());
    }

    @Test
    void aCaptureErrorsOperationReturnsTheErrors() {
        assertEquals("ArticleNotFound", client.queries.captured().getErrors().get(0).getExtensions().get("code"));
    }

    @Test
    void aMutationReturnsItsData() {
        assertEquals("fresh", client.mutations.createArticle(ArticleInput.builder().title("fresh").build()).getCreateArticle().getId());
    }

    @Test
    void aDeclaredErrorCarriesAListField() {
        RuntimeException e = thrownBy(() -> client.mutations.createArticle(ArticleInput.builder().title("taken").build()));
        assertTrue(e instanceof TitleTaken);
        assertEquals("taken", ((TitleTaken) e).getTitle());
        assertEquals(Arrays.asList("taken-2"), ((TitleTaken) e).getSuggestions());
    }

    @Test
    void anErrorWithItsOwnValueAnEnumAndAnOptionalField() {
        RuntimeException e = thrownBy(() -> client.mutations.createArticle(ArticleInput.builder().title("banned").build()));
        assertTrue(e instanceof Banned);
        assertEquals(Reason.SPAM, ((Banned) e).getReason());
        assertEquals(Integer.valueOf(5), ((Banned) e).getUntil());
    }
}
