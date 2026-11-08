package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import static org.junit.jupiter.api.DynamicTest.dynamicTest;

import com.fasterxml.jackson.databind.JsonNode;
import dev.graphlink.rest.generated.client.*;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;

class FaultTest {
    private static final Map<Character, String> OP_NAMES = Map.of('g', "GraphQL getCount", 'c', "REST count", 'p', "REST status");

    private static final Map<String, String> KNOWN_DEFECTS = Map.of();

    private static final Map<String, String> WEBCLIENT_DEFECTS = Map.of(
        "wrong-charset:g", "WebClient rejects a Content-Type with an unknown charset",
        "wrong-charset:c", "WebClient rejects a Content-Type with an unknown charset",
        "wrong-charset:p", "WebClient rejects a Content-Type with an unknown charset");

    private static boolean usesWebClient() {
        for (java.lang.reflect.Field field : DefaultGraphLinkRestAdapter.class.getDeclaredFields()) {
            if (field.getType().getName().endsWith("WebClient")) return true;
        }
        return false;
    }

    private GraphLinkClient client() {
        return newClient(FAULT_URL);
    }

    private static Callable<Object> call(GraphLinkClient client, char op) {
        if (op == 'g') return () -> client.queries.getCount();
        if (op == 'c') return () -> client.queries.count();
        return () -> client.queries.status(200);
    }

    private static void assertHealthy(GraphLinkClient client, char op) {
        if (op == 'g') assertEquals(19, client.queries.getCount().getGetCount());
        else if (op == 'c') assertEquals(7, client.queries.count());
        else assertEquals("Pen", client.queries.status(200).getName());
    }

    @TestFactory
    List<DynamicTest> faults() throws Exception {
        JsonNode cases = MAPPER.readTree(new File("../../fault_server/cases.json"));
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode c : cases) {
            String fault = c.get("fault").asText();
            String expected = c.get("expect").asText();
            for (char op : c.get("ops").asText().toCharArray()) {
                tests.add(dynamicTest(fault + ": " + OP_NAMES.get(op) + " -> " + expected + ", then the client still works", () -> {
                    String defect = KNOWN_DEFECTS.get(fault + ":" + op);
                    if (defect == null && usesWebClient()) defect = WEBCLIENT_DEFECTS.get(fault + ":" + op);
                    assumeTrue(defect == null, defect);
                    postFault("/_reset");
                    GraphLinkClient client = client();
                    postFault("/_arm?fault=" + fault);
                    Object result = null;
                    Throwable error = null;
                    try {
                        result = POOL.submit(call(client, op)).get(8, TimeUnit.SECONDS);
                    } catch (TimeoutException e) {
                        fail(fault + " hung for 8 seconds");
                    } catch (ExecutionException e) {
                        error = e.getCause();
                    }
                    if (expected.equals("value")) assertNull(error, fault + ":" + op + " unexpected failure: " + error);
                    if (expected.equals("failure")) assertNotNull(error, fault + ":" + op + " decoded without a failure: " + result);
                    assertHealthy(client, op);
                }));
            }
        }
        return tests;
    }

    @Test
    void aRestErrorCarriesTheStatusAndTheBodyOfAGatewayPage() throws Exception {
        postFault("/_reset");
        postFault("/_arm?fault=html-502");
        GraphLinkClient client = client();
        RestError error = assertThrows(RestError.class, () -> client.queries.count());
        assertEquals(502, error.getStatus());
        assertTrue(error.getBody().contains("Bad Gateway"));
    }

    @Test
    void aGraphQLErrorReachesTheCallerWithMessagePathAndExtensions() throws Exception {
        postFault("/_reset");
        postFault("/_arm?fault=gql-errors-only");
        GraphLinkClient client = client();
        GraphLinkException error = assertThrows(GraphLinkException.class, () -> client.queries.getCount());
        assertEquals(1, error.getErrors().size());
        assertEquals("boom", error.getErrors().get(0).getMessage());
        assertEquals(List.of("getCount"), error.getErrors().get(0).getPath());
        assertEquals("BAD", error.getErrors().get(0).getExtensions().get("code"));
    }

    @Test
    void aGraphQLCallKeepsTheHttpStatusAndBody() throws Exception {
        String[][] cases = {{"html-502", "502", "Bad Gateway"}, {"status-401-json", "401", "unauthorized"}};
        for (String[] c : cases) {
            postFault("/_reset");
            postFault("/_arm?fault=" + c[0]);
            GraphLinkClient client = client();
            GraphLinkException error = assertThrows(GraphLinkException.class, () -> client.queries.getCount());
            assertEquals(Integer.parseInt(c[1]), error.getErrors().get(0).getStatus(), c[0]);
            assertTrue(error.getErrors().get(0).getBody().contains(c[2]), c[0]);
        }
    }

    @Test
    void aResponseWithoutDataAndWithoutErrorsSaysSo() throws Exception {
        postFault("/_reset");
        postFault("/_arm?fault=gql-empty-object");
        GraphLinkClient client = client();
        GraphLinkException error = assertThrows(GraphLinkException.class, () -> client.queries.getCount());
        assertTrue(error.getErrors().get(0).getMessage().contains("no data"));
    }
}
