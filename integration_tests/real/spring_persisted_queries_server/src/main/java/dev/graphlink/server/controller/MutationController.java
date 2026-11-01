package dev.graphlink.server.controller;

import dev.graphlink.server.DataFixtures;
import dev.graphlink.server.model.*;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.stereotype.Controller;

import java.util.List;

@Controller
public class MutationController {

    @MutationMapping
    public User createUser(@Argument CreateUserInput input) {
        return new User(
            "user-new",
            input.name(),
            input.email(),
            input.status(),
            input.priority(),
            new Address(
                input.address().street(),
                input.address().city(),
                input.address().country(),
                input.address().zip()
            ),
            input.billingAddress() == null ? null : new Address(
                input.billingAddress().street(),
                input.billingAddress().city(),
                input.billingAddress().country(),
                input.billingAddress().zip()
            ),
            input.tags() == null ? List.of() : input.tags(),
            input.initialScore() == null ? null : List.of(input.initialScore()),
            null
        );
    }

    @MutationMapping
    public boolean deleteUser(@Argument String id) {
        return true;
    }

    @MutationMapping
    public User updateUser(@Argument String id, @Argument UpdateUserInput input) {
        User base = DataFixtures.userById(id);
        if (base == null) base = DataFixtures.ALICE;
        return new User(
            base.id(),
            input.name() != null ? input.name() : base.name(),
            input.email() != null ? input.email() : base.email(),
            input.status() != null ? input.status() : base.status(),
            input.priority() != null ? input.priority() : base.priority(),
            base.address(),
            base.billingAddress(),
            input.tags() != null ? input.tags() : base.tags(),
            base.scores(),
            base.posts()
        );
    }

    @MutationMapping
    public User createCachedUser(@Argument CreateUserInput input) {
        return createUser(input);
    }

    @MutationMapping
    public Post transferPost(@Argument String postId, @Argument String newAuthorId) {
        Post post = DataFixtures.postById(postId);
        if (post == null) post = DataFixtures.POST;
        User newAuthor = DataFixtures.userById(newAuthorId);
        if (newAuthor == null) newAuthor = DataFixtures.ALICE;
        return new Post(post.id(), post.title(), post.body(), newAuthor, post.coAuthor(), post.viewCount());
    }

    @MutationMapping
    public boolean resetAll() {
        return true;
    }

    @MutationMapping
    public User createUserOrErrors(@Argument CreateUserInput input) {
        if ("error-user".equals(input.name())) throw graphql.GraphqlErrorException.newErrorException()
                .message("Cannot create user").build();
        return createUser(input);
    }

    // ── Default-value mutation ──────────────────────────────────────────────
    // The SERVER schema has NO defaults — the CLIENT applies them.
    // This resolver just echoes back the values it receives so tests can
    // verify the client sent the correct defaults.

    @MutationMapping
    public DefaultsEcho createWithDefaults(@Argument CreateWithDefaultsInput input) {
        return new DefaultsEcho(
            input.name(),
            input.role(),
            input.age(),
            input.isActive(),
            input.score(),
            input.nickname(),
            input.tags()
        );
    }

    // ── Nested-defaults mutation ────────────────────────────────────────────
    // Tests object, list-of-objects, and list-of-list-of-objects defaults.

    @MutationMapping
    public NestedDefaultsEcho createWithNestedDefaults(@Argument NestedDefaultsInput input) {
        return new NestedDefaultsEcho(
            input.name(),
            input.address() == null ? null : toAddress(input.address()),
            input.contacts() == null ? null : input.contacts().stream().map(this::toAddress).toList(),
            input.matrix() == null ? null : input.matrix().stream()
                .map(row -> row.stream().map(this::toAddress).toList())
                .toList()
        );
    }

    private Address toAddress(AddressInput a) {
        return new Address(a.street(), a.city(), a.country(), a.zip());
    }

    // ── Keyword-collision coverage ──────────────────────────────────────────
    // The input field `class` is a keyword; bind the input as a Map so the Java
    // side never needs a field literally named `class`. Echoes it back through
    // ClassResult (whose `class` field is served via @SchemaMapping).

    @MutationMapping
    public ClassResult makeClass(@Argument("input") java.util.Map<String, Object> input) {
        return new ClassResult("made", (String) input.get("class"));
    }

    // ── Normalization coverage ──────────────────────────────────────────────
    // Input field names (FirstName, last_name, event_type) are non-standard.
    // Bind as a Map to avoid needing a Java type with those exact field names.

    @MutationMapping
    public NormalizedFields createNormalizedRecord(
            @Argument("input") java.util.Map<String, Object> input) {
        String firstName = (String) input.get("FirstName");
        String lastName = (String) input.get("last_name");
        EventType eventType = EventType.valueOf((String) input.get("event_type"));
        return new NormalizedFields("rec-new", firstName, lastName, 0, eventType);
    }
}
