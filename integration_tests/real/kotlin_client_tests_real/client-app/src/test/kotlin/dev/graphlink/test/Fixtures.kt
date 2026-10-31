package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec

object Fixtures {

    const val SERVER_URL = "http://localhost:9999/graphql"
    const val WS_URL = "ws://localhost:9999/graphql"
    const val UPLOAD_URL = "http://localhost:9998/graphql"

    // ── Client factories ──────────────────────────────────────────────────────

    fun newRealClient(): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(
            OkHttpGraphLinkClientAdapter(SERVER_URL),
            MockWebSocketAdapter(),
            MockMultipartAdapter(),
            codec, codec,
        )
    }

    fun newUploadClient(): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(
            OkHttpGraphLinkClientAdapter(SERVER_URL),
            MockWebSocketAdapter(),
            OkHttpMultipartAdapter(UPLOAD_URL),
            codec, codec,
        )
    }

    fun newClient(adapter: MockAdapter, wsAdapter: MockWebSocketAdapter): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(adapter, wsAdapter, MockMultipartAdapter(), codec, codec)
    }

    // ── Address ───────────────────────────────────────────────────────────────

    val kAddressJson = n(
        "street"  to "123 Main St",
        "city"    to "Springfield",
        "country" to "US",
        "zip"     to "12345",
    )

    val kAddressNoZipJson = n(
        "street"  to "456 Oak Ave",
        "city"    to "Shelbyville",
        "country" to "US",
        "zip"     to null,
    )

    val kBillingAddressJson = n(
        "street"  to "789 Pine Rd",
        "city"    to "Capital City",
        "country" to "US",
        "zip"     to "99999",
    )

    // ── Users ─────────────────────────────────────────────────────────────────

    /** Alice — ACTIVE, priority HIGH, no billingAddress, has tags and scores. */
    val kUserAliceJson = n(
        "id"             to "user-1",
        "name"           to "Alice Smith",
        "email"          to "alice@test.com",
        "status"         to "ACTIVE",
        "priority"       to "HIGH",
        "address"        to kAddressJson,
        "billingAddress" to null,
        "tags"           to listOf("admin", "beta"),
        "scores"         to listOf(10, 20, 30),
        "posts"          to null,
    )

    /** Bob — INACTIVE, priority null, has billingAddress, empty tags, null scores. */
    val kUserBobJson = n(
        "id"             to "user-2",
        "name"           to "Bob Jones",
        "email"          to "bob@test.com",
        "status"         to "INACTIVE",
        "priority"       to null,
        "address"        to kAddressNoZipJson,
        "billingAddress" to kBillingAddressJson,
        "tags"           to emptyList<String>(),
        "scores"         to null,
        "posts"          to null,
    )

    // ── AllScalars ────────────────────────────────────────────────────────────

    /** All nullable fields are null. */
    val kAllScalarsNullJson = n(
        "id"            to "scalar-1",
        "strVal"        to "hello world",
        "intVal"        to 42,
        "floatVal"      to 3.14,
        "boolVal"       to true,
        "nullableStr"   to null,
        "nullableInt"   to null,
        "nullableFloat" to null,
        "nullableBool"  to null,
        "nullableId"    to null,
    )

    /** All nullable fields present; also tests negative numbers and false bool. */
    val kAllScalarsPresentJson = n(
        "id"            to "scalar-2",
        "strVal"        to "edge case",
        "intVal"        to -1,
        "floatVal"      to -0.5,
        "boolVal"       to false,
        "nullableStr"   to "present",
        "nullableInt"   to 99,
        "nullableFloat" to 2.718,
        "nullableBool"  to false,
        "nullableId"    to "nid-1",
    )

    // ── Post ──────────────────────────────────────────────────────────────────

    val kPostJson = n(
        "id"        to "post-1",
        "title"     to "Hello World",
        "body"      to "Post body text.",
        "author"    to kUserAliceJson,
        "coAuthor"  to null,
        "viewCount" to 128,
    )

    val kPostWithCoAuthorJson = n(
        "id"        to "post-2",
        "title"     to "Collaboration",
        "body"      to "Written together.",
        "author"    to kUserAliceJson,
        "coAuthor"  to kUserBobJson,
        "viewCount" to 42,
    )

    // ── AuditEntry ────────────────────────────────────────────────────────────

    /** internalNote absent — matches @glSkipOnClient output. */
    val kAuditEntryJson = n(
        "id"          to "audit-1",
        "action"      to "LOGIN",
        "performedBy" to "user-1",
    )

    /** Extra server-only field — client should silently ignore it. */
    val kAuditEntryWithExtraJson = n(
        "id"           to "audit-2",
        "action"       to "LOGOUT",
        "performedBy"  to "user-1",
        "internalNote" to "this should be silently ignored",
    )

    // ── Cyclic fixtures (User → Post → User) ──────────────────────────────────

    /** Post whose author is a minimal User with posts: null (cycle broken here). */
    val kPostWithAuthorCycleJson = n(
        "id"        to "post-10",
        "title"     to "Cyclic Post",
        "body"      to "Body text.",
        "author"    to n(
            "id"             to "user-1",
            "name"           to "Alice Smith",
            "email"          to "alice@test.com",
            "status"         to "ACTIVE",
            "priority"       to "HIGH",
            "address"        to kAddressJson,
            "billingAddress" to null,
            "tags"           to listOf("admin"),
            "scores"         to null,
            "posts"          to null,
        ),
        "coAuthor"  to null,
        "viewCount" to 7,
    )

    /** Alice with one post; post's author has posts: null (cycle broken). */
    val kUserWithPostsJson = n(
        "id"             to "user-1",
        "name"           to "Alice Smith",
        "email"          to "alice@test.com",
        "status"         to "ACTIVE",
        "priority"       to "HIGH",
        "address"        to kAddressJson,
        "billingAddress" to null,
        "tags"           to listOf("admin", "beta"),
        "scores"         to listOf(10, 20, 30),
        "posts"          to listOf(kPostWithAuthorCycleJson),
    )

    // ── Tags ──────────────────────────────────────────────────────────────────

    val kTagsJson = listOf(
        n("id" to "tag-1", "label" to "dart",    "color" to "#0175C2"),
        n("id" to "tag-2", "label" to "graphql", "color" to null),
    )

    // ── Errors ────────────────────────────────────────────────────────────────

    val kGraphQLError = n(
        "message"   to "Not found",
        "locations" to listOf(n("line" to 1, "column" to 1)),
        "path"      to listOf("getUser"),
    )
}

/** Build a Map<String, Any?> that allows null values — shorthand for fixtures. */
fun n(vararg pairs: Pair<String, Any?>): Map<String, Any?> = linkedMapOf(*pairs)
