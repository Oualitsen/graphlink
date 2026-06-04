package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.GetTagsResponse;
import dev.graphlink.test.generated.types.SearchUsersResponse;
import dev.graphlink.test.generated.types.Tag;
import dev.graphlink.test.generated.types.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class ListsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── Non-nullable list of objects ──────────────────────────────────────────

    @Nested
    class NonNullableListOfObjects {

        @Test
        void listUsers_isNotNull() {
            assertNotNull(client.queries.listUsers().getListUsers());
        }

        @Test
        void listUsers_hasTwoItems() {
            assertEquals(2, client.queries.listUsers().getListUsers().size());
        }

        @Test
        void listUsers_firstItem_isUser() {
            assertInstanceOf(User.class, client.queries.listUsers().getListUsers().get(0));
        }

        @Test
        void listUsers_firstItem_hasCorrectId() {
            assertEquals("user-1", client.queries.listUsers().getListUsers().get(0).getId());
        }

        @Test
        void listUsers_secondItem_hasCorrectId() {
            assertEquals("user-2", client.queries.listUsers().getListUsers().get(1).getId());
        }

        @Test
        void listUsers_items_haveDeserializedEnums() {
            List<User> users = client.queries.listUsers().getListUsers();
            assertEquals(UserStatus.ACTIVE, users.get(0).getStatus());
            assertEquals(UserStatus.INACTIVE, users.get(1).getStatus());
        }
    }

    // ── List with nullable item fields ────────────────────────────────────────

    @Nested
    class ListWithNullableItemFields {

        @Test
        void getTags_hasTwoItems() {
            assertEquals(2, client.queries.getTags().getGetTags().size());
        }

        @Test
        void getTags_firstItem_isTag() {
            assertInstanceOf(Tag.class, client.queries.getTags().getGetTags().get(0));
        }

        @Test
        void getTags_firstItem_hasColor() {
            assertEquals("#0175C2",
                    client.queries.getTags().getGetTags().get(0).getColor());
        }

        @Test
        void getTags_secondItem_colorIsNull() {
            assertNull(client.queries.getTags().getGetTags().get(1).getColor());
        }

        @Test
        void getTags_secondItem_hasLabel() {
            assertEquals("graphql",
                    client.queries.getTags().getGetTags().get(1).getLabel());
        }
    }

    // ── List of scalars on a type ─────────────────────────────────────────────

    @Nested
    class ListOfScalars {

        @Test
        void tags_onUser_isListOfStrings() {
            List<String> tags = client.queries.getUser("user-1").getGetUser().getTags();
            assertNotNull(tags);
            assertEquals(2, tags.size());
            assertEquals("admin", tags.get(0));
            assertEquals("beta", tags.get(1));
        }

        @Test
        void tags_empty_returnsEmptyList() {
            List<String> tags = client.queries.getUser("user-2").getGetUser().getTags();
            assertNotNull(tags);
            assertTrue(tags.isEmpty());
        }

        @Test
        void scores_onUser_isListOfIntegers() {
            List<Integer> scores = client.queries.getUser("user-1").getGetUser().getScores();
            assertNotNull(scores);
            assertEquals(List.of(10, 20, 30), scores);
        }
    }

    // ── searchUsers — multi-arg query returning list ───────────────────────────

    @Nested
    class SearchUsers {

        @Test
        void searchUsers_returnsMatchingUsers() {
            SearchUsersResponse res = client.queries.searchUsers("Alice", 10);
            assertNotNull(res.getSearchUsers());
            assertEquals(1, res.getSearchUsers().size());
            assertEquals("user-1", res.getSearchUsers().get(0).getId());
        }

        @Test
        void searchUsers_byName_returnsOnlyMatches() {
            SearchUsersResponse res = client.queries.searchUsers("Bob", 10);
            assertNotNull(res.getSearchUsers());
            assertEquals(1, res.getSearchUsers().size());
            assertEquals("user-2", res.getSearchUsers().get(0).getId());
        }
    }
}
