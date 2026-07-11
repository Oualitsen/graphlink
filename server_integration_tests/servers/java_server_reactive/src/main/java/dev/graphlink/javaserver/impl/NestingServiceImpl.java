package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.Color;
import dev.graphlink.javaserver.generated.services.NestingService;
import dev.graphlink.javaserver.generated.types.Box;
import dev.graphlink.javaserver.generated.types.Circle;
import dev.graphlink.javaserver.generated.interfaces.Shape;
import dev.graphlink.javaserver.generated.interfaces.Media;
import dev.graphlink.javaserver.generated.types.Photo;
import dev.graphlink.javaserver.generated.types.Square;
import dev.graphlink.javaserver.generated.types.Video;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.util.List;

/** List-depth (1/2/3) × nullability × kind (type / interface / union / enum) resolvers. */
@Service
public class NestingServiceImpl implements NestingService {

    private Box box(String id) {
        return Box.builder().id(id).label("label-" + id).build();
    }

    private Circle circle(String id) {
        return Circle.builder().id(id).kind("circle").radius(1).build();
    }

    private Square square(String id) {
        return Square.builder().id(id).kind("square").side(2).build();
    }

    private Photo photo(String id) {
        return Photo.builder().id(id).url("https://x/" + id + ".jpg").width(640).build();
    }

    private Video video(String id) {
        return Video.builder().id(id).url("https://x/" + id + ".mp4").durationSec(30).build();
    }

    @Override
    public Flux<Color> colors1() {
        return Flux.fromIterable(List.of(Color.RED, Color.GREEN, Color.BLUE));
    }

    @Override
    public Flux<List<Color>> colors2() {
        return Flux.fromIterable(List.of(List.of(Color.RED), List.of(Color.GREEN, Color.BLUE)));
    }

    @Override
    public Flux<List<? extends List<Color>>> colors3() {
        return Flux.<List<? extends List<Color>>>fromIterable(List.of(List.of(List.of(Color.RED))));
    }

    @Override
    public Flux<Box> boxes1() {
        return Flux.fromIterable(List.of(box("b1"), box("b2")));
    }

    @Override
    public Flux<List<Box>> boxes2() {
        return Flux.fromIterable(List.of(List.of(box("b1")), List.of(box("b2"))));
    }

    @Override
    public Flux<List<? extends List<Box>>> boxes3() {
        return Flux.<List<? extends List<Box>>>fromIterable(List.of(List.of(List.of(box("b1")))));
    }

    @Override
    public Flux<Shape> shapes1() {
        return Flux.<Shape>fromIterable(List.of(circle("c1"), square("s1")));
    }

    @Override
    public Flux<List<? extends Shape>> shapes2() {
        return Flux.<List<? extends Shape>>fromIterable(List.of(List.of(circle("c1")), List.of(square("s1"))));
    }

    @Override
    public Flux<List<? extends List<? extends Shape>>> shapes3() {
        return Flux.<List<? extends List<? extends Shape>>>fromIterable(List.of(List.of(List.of(circle("c1"), square("s1")))));
    }

    @Override
    public Flux<Media> media1() {
        return Flux.<Media>fromIterable(List.of(photo("p1"), video("v1")));
    }

    @Override
    public Flux<List<? extends Media>> media2() {
        return Flux.<List<? extends Media>>fromIterable(List.of(List.of(photo("p1")), List.of(video("v1"))));
    }

    @Override
    public Flux<List<? extends List<? extends Media>>> media3() {
        return Flux.<List<? extends List<? extends Media>>>fromIterable(List.of(List.of(List.of(photo("p1"), video("v1")))));
    }
}
