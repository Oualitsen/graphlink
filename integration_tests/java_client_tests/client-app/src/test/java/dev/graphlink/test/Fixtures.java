package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;

import java.util.*;

/**
 * Shared JSON fixtures and factory helpers for all integration tests.
 *
 * All fixture maps are Map<String, Object> with null-safe construction
 * (LinkedHashMap so null values are allowed).
 */
public final class Fixtures {

    private Fixtures() {}

    // ── Client factory ────────────────────────────────────────────────────────

    /** Create a fresh GraphLinkClient wired to the given mock adapters (no upload support). */
    public static GraphLinkClient newClient(MockAdapter adapter, MockWebSocketAdapter wsAdapter) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        return new GraphLinkClient(adapter, null, codec, codec, wsAdapter);
    }

    /** Create a fresh GraphLinkClient with upload support. */
    public static GraphLinkClient newClientWithUpload(MockAdapter adapter,
                                                      MockMultipartAdapter multipart,
                                                      MockWebSocketAdapter wsAdapter) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        return new GraphLinkClient(adapter, multipart, codec, codec, wsAdapter);
    }

    // ── Address ───────────────────────────────────────────────────────────────

    public static final Map<String, Object> kAddressJson = map(
            "street",  "123 Main St",
            "city",    "Springfield",
            "country", "US",
            "zip",     "12345"
    );

    public static final Map<String, Object> kAddressNoZipJson = map(
            "street",  "456 Oak Ave",
            "city",    "Shelbyville",
            "country", "US",
            "zip",     null
    );

    public static final Map<String, Object> kBillingAddressJson = map(
            "street",  "789 Pine Rd",
            "city",    "Capital City",
            "country", "US",
            "zip",     "99999"
    );

    // ── Users ─────────────────────────────────────────────────────────────────

    /** Alice — ACTIVE, priority HIGH, no billingAddress, has tags and scores. */
    public static final Map<String, Object> kUserAliceJson = map(
            "id",             "user-1",
            "name",           "Alice Smith",
            "email",          "alice@test.com",
            "status",         "ACTIVE",
            "priority",       "HIGH",
            "address",        kAddressJson,
            "billingAddress", null,
            "tags",           List.of("admin", "beta"),
            "scores",         List.of(10, 20, 30),
            "posts",          null
    );

    /** Bob — INACTIVE, priority null, has billingAddress, empty tags, null scores. */
    public static final Map<String, Object> kUserBobJson = map(
            "id",             "user-2",
            "name",           "Bob Jones",
            "email",          "bob@test.com",
            "status",         "INACTIVE",
            "priority",       null,
            "address",        kAddressNoZipJson,
            "billingAddress", kBillingAddressJson,
            "tags",           Collections.emptyList(),
            "scores",         null,
            "posts",          null
    );

    // ── AllScalars ────────────────────────────────────────────────────────────

    /** All nullable fields are null. */
    public static final Map<String, Object> kAllScalarsNullJson = map(
            "id",            "scalar-1",
            "strVal",        "hello world",
            "intVal",        42,
            "floatVal",      3.14,
            "boolVal",       true,
            "nullableStr",   null,
            "nullableInt",   null,
            "nullableFloat", null,
            "nullableBool",  null,
            "nullableId",    null
    );

    /** All nullable fields have values; also tests negative numbers and false bool. */
    public static final Map<String, Object> kAllScalarsPresentJson = map(
            "id",            "scalar-2",
            "strVal",        "edge case",
            "intVal",        -1,
            "floatVal",      -0.5,
            "boolVal",       false,
            "nullableStr",   "present",
            "nullableInt",   99,
            "nullableFloat", 2.718,
            "nullableBool",  false,
            "nullableId",    "nid-1"
    );

    // ── Post ──────────────────────────────────────────────────────────────────

    public static final Map<String, Object> kPostJson = map(
            "id",        "post-1",
            "title",     "Hello World",
            "body",      "Post body text.",
            "author",    kUserAliceJson,
            "coAuthor",  null,
            "viewCount", 128
    );

    public static final Map<String, Object> kPostWithCoAuthorJson = map(
            "id",        "post-2",
            "title",     "Collaboration",
            "body",      "Written together.",
            "author",    kUserAliceJson,
            "coAuthor",  kUserBobJson,
            "viewCount", 42
    );

    // ── AuditEntry ────────────────────────────────────────────────────────────

    /** internalNote absent — matches @glSkipOnClient output. */
    public static final Map<String, Object> kAuditEntryJson = map(
            "id",          "audit-1",
            "action",      "LOGIN",
            "performedBy", "user-1"
    );

    /** Same entry with an extra server-only field — client should silently ignore it. */
    public static final Map<String, Object> kAuditEntryWithExtraJson = map(
            "id",           "audit-2",
            "action",       "LOGOUT",
            "performedBy",  "user-1",
            "internalNote", "this should be silently ignored"
    );

    // ── Cyclic fixtures (User → Post → User) ──────────────────────────────────

    /** A Post whose author is a minimal User with posts: null (cycle broken here). */
    public static final Map<String, Object> kPostWithAuthorCycleJson = map(
            "id",        "post-10",
            "title",     "Cyclic Post",
            "body",      "Body text.",
            "author",    map(
                    "id",             "user-1",
                    "name",           "Alice Smith",
                    "email",          "alice@test.com",
                    "status",         "ACTIVE",
                    "priority",       "HIGH",
                    "address",        kAddressJson,
                    "billingAddress", null,
                    "tags",           List.of("admin"),
                    "scores",         null,
                    "posts",          null
            ),
            "coAuthor",  null,
            "viewCount", 7
    );

    /** Alice with one post; post's author has posts: null (cycle broken). */
    public static final Map<String, Object> kUserWithPostsJson = map(
            "id",             "user-1",
            "name",           "Alice Smith",
            "email",          "alice@test.com",
            "status",         "ACTIVE",
            "priority",       "HIGH",
            "address",        kAddressJson,
            "billingAddress", null,
            "tags",           List.of("admin", "beta"),
            "scores",         List.of(10, 20, 30),
            "posts",          List.of(kPostWithAuthorCycleJson)
    );

    // ── Tags ──────────────────────────────────────────────────────────────────

    public static final List<Map<String, Object>> kTagsJson = List.of(
            map("id", "tag-1", "label", "dart",    "color", "#0175C2"),
            map("id", "tag-2", "label", "graphql", "color", null)
    );

    // ── Errors ────────────────────────────────────────────────────────────────

    public static final Map<String, Object> kGraphQLError = map(
            "message",   "Not found",
            "locations", List.of(map("line", 1, "column", 1)),
            "path",      List.of("getUser")
    );

    // ── Internal helper ───────────────────────────────────────────────────────

    /**
     * Build a LinkedHashMap from alternating key/value pairs.
     * Allows null values (unlike Map.of).
     */
    @SuppressWarnings("unchecked")
    public static <V> Map<String, V> map(Object... keysAndValues) {
        if (keysAndValues.length % 2 != 0) {
            throw new IllegalArgumentException("keysAndValues must be pairs");
        }
        Map<String, V> m = new LinkedHashMap<>();
        for (int i = 0; i < keysAndValues.length; i += 2) {
            m.put((String) keysAndValues[i], (V) keysAndValues[i + 1]);
        }
        return m;
    }
}
