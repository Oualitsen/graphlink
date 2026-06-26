package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;
import dev.graphlink.test.generated.types.GetCachedUserResponse;
import dev.graphlink.test.generated.types.GetStaleUserResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Cache is 100% client-side logic. These tests use MockAdapter so they can
 * count exact adapter calls and simulate network failure, independent of a
 * running server.
 */
class CacheTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    private static final AddressInput kAddressInput = AddressInput.builder()
            .street("123 Main St").city("Springfield").country("US").zip("12345").build();

    private static final CreateUserInput kCreateInput = CreateUserInput.builder()
            .name("Alice Smith").email("alice@test.com")
            .status(UserStatus.ACTIVE).address(kAddressInput).build();

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── Cache hit ─────────────────────────────────────────────────────────────

    @Nested
    class CacheHit {

        @BeforeEach
        void register() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserAliceJson));
        }

        @Test
        void firstCall_hitsAdapter() {
            client.queries.getCachedUser("user-1").block();
            assertEquals(1, adapter.getCallCount());
        }

        @Test
        void secondCallSameArg_servedFromCache_noExtraAdapterCall() {
            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedUser("user-1").block();
            assertEquals(1, adapter.getCallCount());
        }

        @Test
        void cachedResponse_hasCorrectData() {
            client.queries.getCachedUser("user-1").block();
            GetCachedUserResponse res = client.queries.getCachedUser("user-1").block();
            assertNotNull(res.getGetCachedUser());
            assertEquals("user-1", res.getGetCachedUser().getId());
        }

        @Test
        void differentArg_bypassesCache() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserBobJson));
            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedUser("user-2").block();
            assertEquals(2, adapter.getCallCount());
        }
    }

    // ── Tag-based invalidation ────────────────────────────────────────────────

    @Nested
    class TagInvalidation {

        @Test
        void createCachedUser_invalidatesUsersTag_nextGetCachedUserRefetches() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserAliceJson));
            adapter.registerData("createCachedUser", Map.of("createCachedUser", kUserAliceJson));

            client.queries.getCachedUser("user-1").block();
            assertEquals(1, adapter.getCallCount());

            client.mutations.createCachedUser(kCreateInput).block();
            assertEquals(2, adapter.getCallCount());

            client.queries.getCachedUser("user-1").block();
            assertEquals(3, adapter.getCallCount());
        }

        @Test
        void resetAll_invalidatesAllTags_allCachedQueriesRefetch() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserAliceJson));
            adapter.registerData("getCachedPost", Map.of("getCachedPost", kPostJson));
            adapter.registerData("resetAll", Map.of("resetAll", true));

            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedPost("post-1").block();
            assertEquals(2, adapter.getCallCount());

            client.mutations.resetAll().block();
            assertEquals(3, adapter.getCallCount());

            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedPost("post-1").block();
            assertEquals(5, adapter.getCallCount());
        }
    }

    // ── Cross-tag isolation ───────────────────────────────────────────────────

    @Nested
    class CrossTagIsolation {

        @Test
        void usersTagInvalidation_doesNotAffect_postsCache() {
            adapter.registerData("getCachedPost", Map.of("getCachedPost", kPostJson));
            adapter.registerData("createCachedUser", Map.of("createCachedUser", kUserAliceJson));

            client.queries.getCachedPost("post-1").block();
            assertEquals(1, adapter.getCallCount());

            client.mutations.createCachedUser(kCreateInput).block();
            assertEquals(2, adapter.getCallCount());

            client.queries.getCachedPost("post-1").block();
            assertEquals(2, adapter.getCallCount());
        }

        @Test
        void transferPost_invalidatesBothTags() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserAliceJson));
            adapter.registerData("getCachedPost", Map.of("getCachedPost", kPostJson));
            adapter.registerData("transferPost", Map.of("transferPost", kPostJson));

            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedPost("post-1").block();
            assertEquals(2, adapter.getCallCount());

            client.mutations.transferPost("post-1", "user-2").block();
            assertEquals(3, adapter.getCallCount());

            client.queries.getCachedUser("user-1").block();
            client.queries.getCachedPost("post-1").block();
            assertEquals(5, adapter.getCallCount());
        }
    }

    // ── listCachedUsers ───────────────────────────────────────────────────────

    @Nested
    class ListCachedUsers {

        @Test
        void listCachedUsers_isCachedAfterFirstCall() {
            adapter.registerData("listCachedUsers",
                    Map.of("listCachedUsers", List.of(kUserAliceJson)));
            client.queries.listCachedUsers().block();
            client.queries.listCachedUsers().block();
            assertEquals(1, adapter.getCallCount());
        }

        @Test
        void createCachedUser_invalidatesListCachedUsers() {
            adapter.registerData("listCachedUsers",
                    Map.of("listCachedUsers", List.of(kUserAliceJson)));
            adapter.registerData("createCachedUser", Map.of("createCachedUser", kUserAliceJson));

            client.queries.listCachedUsers().block();
            client.mutations.createCachedUser(kCreateInput).block();
            client.queries.listCachedUsers().block();
            assertEquals(3, adapter.getCallCount());
        }
    }

    // ── staleIfOffline ────────────────────────────────────────────────────────

    @Nested
    class StaleIfOffline {

        @Test
        void staleData_isReturnedWhenNetworkFails_afterTtlExpires() throws InterruptedException {
            adapter.registerData("getStaleUser", map("getStaleUser", kUserAliceJson));

            client.queries.getStaleUser("user-1").block();
            assertEquals(1, adapter.getCallCount());

            Thread.sleep(1100);

            adapter.simulateFailure = true;
            GetStaleUserResponse res = client.queries.getStaleUser("user-1").block();

            assertNotNull(res.getGetStaleUser());
            assertEquals("user-1", res.getGetStaleUser().getId());
        }

        @Test
        void nonStaleEntry_throwsWhenNetworkFails() {
            adapter.registerData("getCachedUser", Map.of("getCachedUser", kUserAliceJson));
            adapter.simulateFailure = true;
            assertThrows(RuntimeException.class,
                    () -> client.queries.getCachedUser("user-1").block());
        }
    }
}
