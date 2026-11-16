package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.GraphLinkError;
import dev.graphlink.test.generated.types.GetUserOrErrorsFullResponse;
import dev.graphlink.test.generated.types.PartialAliasedFullResponse;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class ErrorDetailsTest {

    private final GraphLinkClient client = newRealClient();

    @Test
    void errorCarriesMessagePathLocationsAndTypedExtensions() {
        GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("missing");
        assertEquals(1, res.getErrors().size());
        GraphLinkError e = res.getErrors().get(0);
        assertEquals("User not found: missing", e.getMessage());
        assertEquals(List.of("getUserOrErrors"), e.getPath());
        assertEquals(1, e.getLocations().get(0).getLine());
        assertEquals("NOT_FOUND", e.getExtensions().get("code"));
        assertEquals(Boolean.FALSE, e.getExtensions().get("retryable"));
        Map<?, ?> detail = (Map<?, ?>) e.getExtensions().get("detail");
        assertEquals("missing", detail.get("id"));
        assertEquals(3, ((Number) detail.get("attempts")).intValue());
    }

    @Test
    void partialDataOkIsReturnedBadIsNullAndTheErrorPathIsTheAlias() {
        PartialAliasedFullResponse res = client.queries.partialAliased();
        assertEquals("user-1", res.getData().getOk().getId());
        assertNull(res.getData().getBad());
        assertEquals(1, res.getErrors().size());
        assertEquals(List.of("bad"), res.getErrors().get(0).getPath());
    }
}
