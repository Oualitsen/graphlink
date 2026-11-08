package dev.graphlink.server.controller;

import dev.graphlink.server.model.*;
import graphql.GraphqlErrorException;
import graphql.schema.DataFetchingEnvironment;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

@Controller
public class PolymorphismExtrasController {

    private static final Photo PHOTO = new Photo("ph1", "http://cdn/1.png", 640);
    private static final Video VIDEO = new Video("v1", "http://cdn/1.mp4", 30);
    private static final Document DOCUMENT = new Document("d1", "http://cdn/1.pdf", 12);
    private static final Comment COMMENT = new Comment("c1", "bob", "Nice", null);
    private static final Article FIRST = new Article(
        "a1", "alice", "Hello", PHOTO, List.of(PHOTO, VIDEO, DOCUMENT), Arrays.asList(COMMENT, null));
    private static final Article SECOND = new Article("a2", "bob", "Second", null, List.of(), null);

    @QueryMapping
    public Chain chain(@Argument String id) {
        return switch (id) {
            case "l1" -> new Link("l1", new Link("l2", new End("e1", "done")));
            case "e1" -> new End("e1", "done");
            default -> null;
        };
    }

    @QueryMapping
    public Grid grid(@Argument Boolean empty) {
        if (Boolean.TRUE.equals(empty)) {
            return new Grid(List.of(), List.of(), null);
        }
        return new Grid(
            List.of(Arrays.asList(PHOTO, null), List.of(VIDEO), List.of()),
            List.of(List.of(FIRST, COMMENT), List.of(SECOND)),
            List.of(List.of(PHOTO, DOCUMENT)));
    }

    private static final Stamp STAMP = new Stamp("s1", "2026-01-02T03:04:05Z", 4294967296L);
    private static final Span SPAN = new Span("sp1", "2026-02-03T04:05:06Z", "2026-02-04", "o-9", List.of("2026-03-04T05:06:07Z"));

    @QueryMapping
    public List<Moment> moments() {
        return List.of(STAMP, SPAN);
    }

    @QueryMapping
    public List<Timed> timed() {
        return List.of(SPAN, STAMP);
    }

    private static final AtomicInteger FETCHES = new AtomicInteger();

    @QueryMapping
    public List<Attachment> cachedAttachments() {
        int n = FETCHES.incrementAndGet();
        return List.of(PHOTO, new Video(VIDEO.id(), VIDEO.url(), VIDEO.seconds() + n), DOCUMENT);
    }

    @QueryMapping
    public List<Attachment> failingAttachments(@Argument boolean fail) {
        if (fail) {
            throw GraphqlErrorException.newErrorException().message("attachments failed").build();
        }
        return List.of(PHOTO, VIDEO, DOCUMENT);
    }

    @MutationMapping
    public List<Attachment> bulkAttachments(@Argument int n) {
        List<Attachment> cycle = List.of(PHOTO, VIDEO, DOCUMENT);
        List<Attachment> out = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            out.add(cycle.get(i % cycle.size()));
        }
        return out;
    }

    @MutationMapping
    public List<Entity> bulkEntities() {
        return List.of(FIRST, COMMENT, SECOND);
    }

    @SubscriptionMapping
    public Flux<List<Attachment>> attachmentsBatch() {
        return Flux.just(List.of(PHOTO, VIDEO, DOCUMENT), List.of(DOCUMENT));
    }

    @SubscriptionMapping
    public Flux<List<Entity>> entityBatch() {
        return Flux.just(List.of(FIRST, COMMENT));
    }

    @QueryMapping
    public String describePick(DataFetchingEnvironment env) {
        return describe(env.getArgument("pick"));
    }

    @QueryMapping
    public String describeBasket(DataFetchingEnvironment env) {
        return describe(env.getArgument("basket"));
    }

    private static String describe(Object value) {
        if (value instanceof Map<?, ?> map) {
            return new TreeMap<>(map).entrySet().stream()
                .filter(e -> e.getValue() != null)
                .map(e -> e.getKey() + "=" + describe(e.getValue()))
                .collect(Collectors.joining(", ", "{", "}"));
        }
        if (value instanceof List<?> list) {
            return list.stream().map(PolymorphismExtrasController::describe).collect(Collectors.joining(", ", "[", "]"));
        }
        return String.valueOf(value);
    }
}
