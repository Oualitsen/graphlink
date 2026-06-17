package dev.graphlink.server.controller;

import dev.graphlink.server.DataFixtures;
import dev.graphlink.server.model.*;
import graphql.GraphqlErrorException;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.stereotype.Controller;

import java.util.List;

@Controller
public class QueryController {

    @QueryMapping
    public User getUser(@Argument String id) {
        User user = DataFixtures.userById(id);
        if (user == null) throw GraphqlErrorException.newErrorException()
                .message("User not found: " + id).build();
        return user;
    }

    @QueryMapping
    public User findUser(@Argument String id) {
        if ("error-id".equals(id)) throw GraphqlErrorException.newErrorException()
                .message("User not found: " + id).build();
        return DataFixtures.userById(id);
    }

    @QueryMapping
    public List<User> listUsers() {
        return List.of(DataFixtures.ALICE, DataFixtures.BOB);
    }

    @QueryMapping
    public List<User> listUsersByStatus(@Argument UserStatus status) {
        return List.of(DataFixtures.ALICE, DataFixtures.BOB).stream()
                .filter(u -> u.status() == status)
                .toList();
    }

    @QueryMapping
    public List<User> searchUsers(@Argument String name, @Argument int limit) {
        return List.of(DataFixtures.ALICE, DataFixtures.BOB).stream()
                .filter(u -> u.name().toLowerCase().contains(name.toLowerCase()))
                .limit(limit)
                .toList();
    }

    @QueryMapping
    public AllScalars getAllScalars(@Argument String id) {
        return DataFixtures.scalarById(id);
    }

    @QueryMapping
    public Post getPost(@Argument String id) {
        Post post = DataFixtures.postById(id);
        if (post == null) throw GraphqlErrorException.newErrorException()
                .message("Post not found: " + id).build();
        return post;
    }

    @QueryMapping
    public List<Tag> getTags() {
        return DataFixtures.TAGS;
    }

    @QueryMapping
    public AuditEntry getAuditEntry(@Argument String id) {
        return DataFixtures.auditById(id);
    }

    @QueryMapping
    public List<SearchResult> search(@Argument String term) {
        return List.of(
            new UserResult("user-1", "Alice Smith", "alice@test.com"),
            new PostResult("post-1", "Hello World")
        );
    }

    // ── Cached queries (same data, caching is client-side) ────────────────────

    @QueryMapping
    public User getCachedUser(@Argument String id) {
        return getUser(id);
    }

    @QueryMapping
    public List<User> listCachedUsers() {
        return listUsers();
    }

    @QueryMapping
    public Post getCachedPost(@Argument String id) {
        return getPost(id);
    }

    @QueryMapping
    public AllScalars getCachedConfig() {
        return DataFixtures.ALL_SCALARS_NULL;
    }

    @QueryMapping
    public User getStaleUser(@Argument String id) {
        return DataFixtures.userById(id);
    }

    // ── Error-capture queries ─────────────────────────────────────────────────

    @QueryMapping
    public User getUserOrErrors(@Argument String id) {
        return getUser(id);
    }

    @QueryMapping
    public User findUserOrErrors(@Argument String id) {
        return findUser(id);
    }

    // ── Default-value query ─────────────────────────────────────────────────
    // The SERVER schema has NO defaults — the CLIENT applies them.
    // All args are non-null because the client always sends values.

    @QueryMapping
    public List<User> listUsersWithDefaults(@Argument int limit, @Argument Role role) {
        return List.of(DataFixtures.ALICE, DataFixtures.BOB).stream()
                .limit(limit)
                .toList();
    }

    // ── Driver with field-level argument defaults ───────────────────────────
    // The SERVER schema has NO defaults on field arguments — the CLIENT applies them.
    // Field resolvers return the count argument directly so tests can verify
    // the client sent the correct value (or the default).

    @QueryMapping
    public Driver getDriver(@Argument String id) {
        return new Driver(id);
    }

    @SchemaMapping(typeName = "Driver", field = "lastUsedMillage")
    public int lastUsedMillage(Driver driver, @Argument int odometerKm) {
        return odometerKm;
    }

    @SchemaMapping(typeName = "Driver", field = "lastUsedFuel")
    public int lastUsedFuel(Driver driver, @Argument int liters) {
        return liters;
    }
}
