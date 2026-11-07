package dev.graphlink.server.controller;

import dev.graphlink.server.model.*;
import graphql.GraphqlErrorException;
import java.util.Arrays;
import java.util.List;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

@Controller
public class PolymorphismController {

    private static final Photo PHOTO = new Photo("ph1", "http://cdn/1.png", 640);
    private static final Video VIDEO = new Video("v1", "http://cdn/1.mp4", 30);
    private static final Document DOCUMENT = new Document("d1", "http://cdn/1.pdf", 12);

    private static final Comment COMMENT = new Comment("c1", "bob", "Nice", null);
    private static final Article FIRST = new Article(
        "a1", "alice", "Hello", PHOTO, List.of(PHOTO, VIDEO, DOCUMENT), Arrays.asList(COMMENT, null));
    private static final Article SECOND = new Article("a2", "bob", "Second", null, List.of(), null);
    private static final Comment REPLY = new Comment("c2", "alice", "Thanks", FIRST);

    @QueryMapping
    public List<Entity> feed() {
        return List.of(FIRST, COMMENT, SECOND, REPLY);
    }

    @QueryMapping
    public Node node(@Argument String id) {
        return feed().stream().filter(e -> e.id().equals(id)).findFirst().orElse(null);
    }

    private static final Phone PHONE = new Phone("p1", 6, "Pixel");
    private static final Laptop LAPTOP = new Laptop("l1", "15 inch", "M3");

    @QueryMapping
    public Gadget gadget(@Argument String id) {
        return switch (id) {
            case "p1" -> PHONE;
            case "l1" -> LAPTOP;
            default -> null;
        };
    }

    @QueryMapping
    public List<Gadget> gadgets() {
        return List.of(PHONE, LAPTOP);
    }

    @QueryMapping
    public Photo photo(@Argument String id) {
        return "ph1".equals(id) ? PHOTO : null;
    }

    @QueryMapping
    public Shareable shareable(@Argument String id) {
        return switch (id) {
            case "ph1" -> PHOTO;
            case "p1" -> PHONE;
            default -> null;
        };
    }

    private static final Playlist MIX = new Playlist("pl1", "Mix", 12, null);
    private static final Album SUMMER = new Album("al1", "Summer", 2020, MIX);
    private static final Album WINTER = new Album("al2", "Winter", 2021, null);
    private static final List<Attachment> ITEMS = List.of(PHOTO, VIDEO, DOCUMENT);

    @QueryMapping
    public Listing listing(@Argument String id) {
        return listings().stream().filter(l -> idOf(l).equals(id)).findFirst().orElse(null);
    }

    @QueryMapping
    public List<Listing> listings() {
        return List.of(SUMMER, MIX, WINTER);
    }

    @QueryMapping
    public Solo solo() {
        return SUMMER;
    }

    @SchemaMapping(typeName = "Album", field = "items")
    public List<Attachment> albumItems(Album album, @Argument int limit) {
        return ITEMS.stream().limit(limit).toList();
    }

    @SchemaMapping(typeName = "Playlist", field = "items")
    public List<Attachment> playlistItems(Playlist playlist, @Argument int limit) {
        return ITEMS.stream().skip(1).limit(limit).toList();
    }

    private static String idOf(Listing listing) {
        return listing instanceof Album a ? a.id() : ((Playlist) listing).id();
    }

    @QueryMapping
    public Attachment attachment(@Argument String id) {
        return switch (id) {
            case "ph1" -> PHOTO;
            case "v1" -> VIDEO;
            case "d1" -> DOCUMENT;
            default -> null;
        };
    }

    @QueryMapping
    public List<Attachment> attachments() {
        return List.of(PHOTO, VIDEO, DOCUMENT);
    }

    @QueryMapping
    public List<Attachment> attachmentsNullable() {
        return Arrays.asList(PHOTO, null, DOCUMENT);
    }

    @QueryMapping
    public Article article(@Argument String id) {
        return switch (id) {
            case "a1" -> FIRST;
            case "a2" -> SECOND;
            default -> throw GraphqlErrorException.newErrorException().message("Article not found: " + id).build();
        };
    }

    @QueryMapping
    public Attachment getCachedAttachment(@Argument String id) {
        return attachment(id);
    }

    @QueryMapping
    public Attachment attachmentOrErrors(@Argument String id) {
        if ("boom".equals(id)) {
            throw GraphqlErrorException.newErrorException().message("Attachment failed: " + id).build();
        }
        return attachment(id);
    }

    @MutationMapping
    public Attachment addAttachment(@Argument String articleId, @Argument String url, @Argument String kind) {
        return switch (kind) {
            case "photo" -> new Photo("new-photo", url, 1);
            case "video" -> new Video("new-video", url, 1);
            case "document" -> new Document("new-document", url, 1);
            default -> throw GraphqlErrorException.newErrorException().message("Unknown kind: " + kind).build();
        };
    }

    @SubscriptionMapping
    public Flux<Attachment> attachmentAdded() {
        return Flux.just(PHOTO, VIDEO, DOCUMENT);
    }

    @SubscriptionMapping
    public Flux<Entity> entityPublished() {
        return Flux.just(FIRST, COMMENT);
    }
}
