package dev.graphlink.server;

import dev.graphlink.server.model.*;

import java.util.List;

public final class DataFixtures {

    private DataFixtures() {}

    public static final Address ADDRESS = new Address("123 Main St", "Springfield", "US", "12345");
    public static final Address ADDRESS_NO_ZIP = new Address("456 Oak Ave", "Shelbyville", "US", null);
    public static final Address BILLING_ADDRESS = new Address("789 Pine Rd", "Capital City", "US", "99999");

    public static final User ALICE = new User(
        "user-1", "Alice Smith", "alice@test.com",
        UserStatus.ACTIVE, Priority.HIGH,
        ADDRESS, null,
        List.of("admin", "beta"), List.of(10, 20, 30), null
    );

    public static final User BOB = new User(
        "user-2", "Bob Jones", "bob@test.com",
        UserStatus.INACTIVE, null,
        ADDRESS_NO_ZIP, BILLING_ADDRESS,
        List.of(), null, null
    );

    // Alice with minimal posts field (cycle broken — post author has posts=null)
    public static final Post POST_WITH_AUTHOR_CYCLE = new Post(
        "post-10", "Cyclic Post", "Body text.",
        new User("user-1", "Alice Smith", "alice@test.com",
            UserStatus.ACTIVE, Priority.HIGH, ADDRESS, null,
            List.of("admin"), null, null),
        null, 7
    );

    // Recent posts for ALICE_WITH_POSTS — author cycle broken (posts=null) like
    // POST_WITH_AUTHOR_CYCLE, used to exercise field-level arguments via recentPosts(limit:).
    private static final User ALICE_NO_POSTS = new User(
        "user-1", "Alice Smith", "alice@test.com",
        UserStatus.ACTIVE, Priority.HIGH, ADDRESS, null,
        List.of("admin", "beta"), List.of(10, 20, 30), null
    );

    public static final Post POST_RECENT_1 =
        new Post("post-20", "Recent Post 1", "Body 1.", ALICE_NO_POSTS, null, 5);
    public static final Post POST_RECENT_2 =
        new Post("post-21", "Recent Post 2", "Body 2.", ALICE_NO_POSTS, null, 8);
    public static final Post POST_RECENT_3 =
        new Post("post-22", "Recent Post 3", "Body 3.", ALICE_NO_POSTS, null, 13);

    public static final User ALICE_WITH_POSTS = new User(
        "user-1", "Alice Smith", "alice@test.com",
        UserStatus.ACTIVE, Priority.HIGH,
        ADDRESS, null,
        List.of("admin", "beta"), List.of(10, 20, 30),
        List.of(POST_WITH_AUTHOR_CYCLE, POST_RECENT_1, POST_RECENT_2, POST_RECENT_3)
    );

    public static final Post POST = new Post(
        "post-1", "Hello World", "Post body text.", ALICE, null, 128
    );

    public static final Post POST_WITH_CO_AUTHOR = new Post(
        "post-2", "Collaboration", "Written together.", ALICE, BOB, 42
    );

    public static final AllScalars ALL_SCALARS_NULL = new AllScalars(
        "scalar-1", "hello world", 42, 3.14, true,
        null, null, null, null, null
    );

    public static final AllScalars ALL_SCALARS_PRESENT = new AllScalars(
        "scalar-2", "edge case", -1, -0.5, false,
        "present", 99, 2.718, false, "nid-1"
    );

    public static final List<Tag> TAGS = List.of(
        new Tag("tag-1", "dart", "#0175C2"),
        new Tag("tag-2", "graphql", null)
    );

    public static final AuditEntry AUDIT_ENTRY = new AuditEntry(
        "audit-1", "LOGIN", "user-1", "internal log detail"
    );

    public static final AuditEntry AUDIT_ENTRY_2 = new AuditEntry(
        "audit-2", "LOGOUT", "user-1", "this should be silently ignored"
    );

    public static User userById(String id) {
        return switch (id) {
            case "user-1" -> ALICE;
            case "user-2" -> BOB;
            case "user-with-posts" -> ALICE_WITH_POSTS;
            default -> null;
        };
    }

    public static Post postById(String id) {
        return switch (id) {
            case "post-1" -> POST;
            case "post-2" -> POST_WITH_CO_AUTHOR;
            case "post-10" -> POST_WITH_AUTHOR_CYCLE;
            default -> null;
        };
    }

    public static AllScalars scalarById(String id) {
        return switch (id) {
            case "scalar-1" -> ALL_SCALARS_NULL;
            case "scalar-2" -> ALL_SCALARS_PRESENT;
            default -> ALL_SCALARS_NULL;
        };
    }

    public static AuditEntry auditById(String id) {
        return switch (id) {
            case "audit-1" -> AUDIT_ENTRY;
            case "audit-2" -> AUDIT_ENTRY_2;
            default -> AUDIT_ENTRY;
        };
    }
}
