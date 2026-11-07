package dev.graphlink.server.controller;

import dev.graphlink.server.model.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.IntStream;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class ListsController {

    private static final Photo PHOTO = new Photo("ph1", "http://cdn/1.png", 640);
    private static final Video VIDEO = new Video("v1", "http://cdn/1.mp4", 30);
    private static final Comment COMMENT = new Comment("c1", "bob", "Nice", null);

    @QueryMapping
    public ListShapes listShapes(@Argument String mode) {
        return switch (mode) {
            case "full" -> new ListShapes(
                List.of(1, 2, 3),
                List.of(1, 2, 3),
                Arrays.asList(1, null, 3),
                Arrays.asList((Integer) null),
                List.of(List.of(1, 2), List.of(3)),
                Arrays.asList(Arrays.asList(1, null), null),
                Arrays.asList(Spelling.A, null, Spelling.B2),
                Arrays.asList(PHOTO, null),
                Arrays.asList(PHOTO, null, VIDEO),
                Arrays.asList(COMMENT, null));
            case "empty" -> new ListShapes(
                List.of(), List.of(), List.of(), List.of(), List.of(), List.of(),
                List.of(), List.of(), List.of(), List.of());
            default -> new ListShapes(
                List.of(), null, List.of(), null, List.of(), null,
                List.of(), List.of(), List.of(), List.of());
        };
    }

    @QueryMapping
    public List<Integer> bigInts(@Argument int n) {
        return IntStream.range(0, n).boxed().toList();
    }

    @QueryMapping
    public List<Photo> bigPhotos(@Argument int n) {
        List<Photo> out = new ArrayList<>(n);
        for (int i = 0; i < n; i++) {
            out.add(new Photo("p" + i, "http://cdn/" + i, i));
        }
        return out;
    }

    @QueryMapping
    public ListsEcho echoArgs(
        @Argument List<Integer> a,
        @Argument List<Integer> b,
        @Argument List<List<Integer>> c,
        @Argument List<Spelling> e,
        @Argument List<Spelling> f,
        @Argument List<Spelling> g,
        @Argument OnlyOne one) {
        return new ListsEcho(a, b, c, e, f, g, one);
    }

    @QueryMapping
    public ListsEcho echoInput(@Argument ListsInput input) {
        return new ListsEcho(input.a(), input.b(), input.c(), input.e(), input.f(), input.g(), input.one());
    }

    @QueryMapping
    public String argOnly(@Argument ArgOnly v) {
        return v.name();
    }

    @QueryMapping
    public RespOnly respOnly() {
        return RespOnly.R2;
    }

    @QueryMapping
    public PhaseProbe phaseProbe() {
        return new PhaseProbe(Phase.ARCHIVED, Phase.ARCHIVED,
            List.of(Phase.OPEN, Phase.ARCHIVED, Phase.CLOSED), Arrays.asList(Phase.ARCHIVED, null));
    }

    @QueryMapping
    public PhaseHolder phaseHolder() {
        return new Phased(Phase.ARCHIVED);
    }
}
