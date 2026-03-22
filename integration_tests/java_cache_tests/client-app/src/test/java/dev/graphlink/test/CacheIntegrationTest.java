package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.inputs.CreateCarInput;
import dev.graphlink.test.generated.inputs.CreateOwnerInput;
import dev.graphlink.test.generated.interfaces.GraphLinkJsonDecoder;
import dev.graphlink.test.generated.interfaces.GraphLinkJsonEncoder;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class CacheIntegrationTest {

    private static final String SERVER_URL = "http://localhost:8080/graphql";
    private static final String JAR_PATH = System.getProperty(
            "spring.jar.path",
            "../../cache_tests/spring-server/target/graphql-server-0.0.1-SNAPSHOT.jar"
    );

    private static Process serverProcess;
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final HttpClient http = HttpClient.newHttpClient();

    private final AtomicInteger serverCallCount = new AtomicInteger(0);
    private final AtomicBoolean simulateOffline = new AtomicBoolean(false);

    private GraphLinkClient client;

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    @BeforeAll
    static void startServer() throws Exception {
        serverProcess = new ProcessBuilder("java", "-jar", JAR_PATH)
                .redirectErrorStream(true)
                .start();

        // drain stdout so the process doesn't block on a full pipe
        Thread stdoutDrain = new Thread(() -> {
            try { serverProcess.getInputStream().transferTo(System.out); } catch (IOException ignored) {}
        });
        stdoutDrain.setDaemon(true);
        stdoutDrain.start();

        waitForServer();
    }

    @AfterAll
    static void stopServer() {
        if (serverProcess != null) serverProcess.destroyForcibly();
    }

    @BeforeEach
    void setUp() {
        serverCallCount.set(0);
        simulateOffline.set(false);

        GraphLinkJsonEncoder encoder = obj -> {
            try {
                return mapper.writeValueAsString(obj);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };

        GraphLinkJsonDecoder decoder = json -> {
            try {
                //noinspection unchecked
                return (Map<String, Object>) mapper.readValue(json, Map.class);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };

        var adapter = (dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter) payload -> {
            if (simulateOffline.get()) throw new RuntimeException("Network unreachable");
            serverCallCount.incrementAndGet();
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(SERVER_URL))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();
            try {
                HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() != 200) {
                    throw new RuntimeException("Server error: " + response.statusCode() + " " + response.body());
                }
                return response.body();
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };

        client = new GraphLinkClient(adapter, encoder, decoder, null);
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    @Test
    @Order(1)
    void getCar_isServedFromCache_onSecondCallWithSameId() {
        var created = client.mutations.createCar(
                CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build()
        );
        String carId = created.getCreateCar().getId();

        client.queries.getCar(carId);
        int countAfterFirst = serverCallCount.get();

        client.queries.getCar(carId);
        int countAfterSecond = serverCallCount.get();

        assertEquals(countAfterFirst, countAfterSecond, "second getCar should hit cache, not the server");
    }

    @Test
    @Order(2)
    void getCar_withDifferentIds_hitsServerEachTime() {
        var car1 = client.mutations.createCar(
                CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build()
        );
        var car2 = client.mutations.createCar(
                CreateCarInput.builder().make("Honda").model("Civic").year(2022).build()
        );

        serverCallCount.set(0);
        client.queries.getCar(car1.getCreateCar().getId());
        client.queries.getCar(car2.getCreateCar().getId());

        assertEquals(2, serverCallCount.get(), "different ids must each go to the server");
    }

    @Test
    @Order(3)
    void getCarAndOwner_servesPartialResultFromCache_afterCarsTagInvalidation() {
        var createdCar = client.mutations.createCar(
                CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build()
        );
        var createdOwner = client.mutations.createOwner(
                CreateOwnerInput.builder().name("Alice").email("alice@example.com").build()
        );
        String carId = createdCar.getCreateCar().getId();
        String ownerId = createdOwner.getCreateOwner().getId();

        // warm up both sub-query caches
        client.queries.getCarAndOwner(carId, ownerId);
        serverCallCount.set(0);

        // fully cached — no network call expected
        client.queries.getCarAndOwner(carId, ownerId);
        assertEquals(0, serverCallCount.get(), "both sub-queries should be served from cache");

        // invalidate the "cars" tag — only the car sub-query cache entry is busted
        client.mutations.createCar(
                CreateCarInput.builder().make("Honda").model("Civic").year(2022).build()
        );
        serverCallCount.set(0);

        // partial fetch: car must come from network, getOwner still from cache
        client.queries.getCarAndOwner(carId, ownerId);
        assertEquals(1, serverCallCount.get(),
                "only the car sub-query should hit the server; getOwner is still cached");
    }

    @Test
    @Order(4)
    void getCarStale_returnsStaleData_whenNetworkFailsAfterCacheExpires() throws InterruptedException {
        var created = client.mutations.createCar(
                CreateCarInput.builder().make("Ford").model("Focus").year(2020).build()
        );
        String carId = created.getCreateCar().getId();

        // warm the cache (TTL = 1 second)
        var fresh = client.queries.getCarStale(carId);
        assertEquals(carId, fresh.getGetCarStale().getId());

        // let the cache entry expire
        Thread.sleep(2000);

        // go offline — staleIfOffline: true should return the expired entry
        simulateOffline.set(true);
        var stale = client.queries.getCarStale(carId);
        assertEquals(carId, stale.getGetCarStale().getId());
    }

    @Test
    @Order(5)
    void getCarExpiring_throwsWhenNetworkFails_afterCacheExpires() throws InterruptedException {
        var created = client.mutations.createCar(
                CreateCarInput.builder().make("Ford").model("Focus").year(2020).build()
        );
        String carId = created.getCreateCar().getId();

        // warm the cache (TTL = 1 second)
        client.queries.getCarExpiring(carId);

        // let the cache entry expire
        Thread.sleep(2000);

        // go offline — staleIfOffline defaults to false, so it must throw
        simulateOffline.set(true);
        assertThrows(RuntimeException.class, () -> client.queries.getCarExpiring(carId));
    }

    @Test
    @Order(6)
    void getCar_cacheIsInvalidated_afterCreateCarMutation() {
        var created = client.mutations.createCar(
                CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build()
        );
        String carId = created.getCreateCar().getId();

        client.queries.getCar(carId);
        serverCallCount.set(0);

        // this mutation carries @glCacheInvalidate(tags: ["cars"]) — busts getCar cache
        client.mutations.createCar(
                CreateCarInput.builder().make("Honda").model("Civic").year(2022).build()
        );
        serverCallCount.set(0);

        client.queries.getCar(carId);
        assertEquals(1, serverCallCount.get(), "getCar should hit server after cache invalidation");
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static void waitForServer() throws Exception {
        String probe = mapper.writeValueAsString(Map.of("query", "{ getCarsCount }"));
        for (int i = 0; i < 30; i++) {
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(SERVER_URL))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(probe))
                        .build();
                http.send(request, HttpResponse.BodyHandlers.ofString());
                return;
            } catch (IOException ignored) {
                Thread.sleep(1000);
            }
        }
        throw new RuntimeException("Server did not start in time");
    }
}
