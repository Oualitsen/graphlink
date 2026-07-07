package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.Color;
import dev.graphlink.javaserver.generated.services.NestingService;
import dev.graphlink.javaserver.generated.types.Box;
import dev.graphlink.javaserver.generated.types.Circle;
import dev.graphlink.javaserver.generated.interfaces.Shape;
import dev.graphlink.javaserver.generated.types.Square;
import org.springframework.stereotype.Service;

import java.util.List;

/** List-depth (1/2/3) × nullability × kind (type / interface / enum) resolvers. */
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

    @Override
    public List<Color> colors1() {
        return List.of(Color.RED, Color.GREEN, Color.BLUE);
    }

    @Override
    public List<? extends List<Color>> colors2() {
        return List.of(List.of(Color.RED), List.of(Color.GREEN, Color.BLUE));
    }

    @Override
    public List<? extends List<? extends List<Color>>> colors3() {
        return List.of(List.of(List.of(Color.RED)));
    }

    @Override
    public List<Box> boxes1() {
        return List.of(box("b1"), box("b2"));
    }

    @Override
    public List<? extends List<Box>> boxes2() {
        return List.of(List.of(box("b1")), List.of(box("b2")));
    }

    @Override
    public List<? extends List<? extends List<Box>>> boxes3() {
        return List.of(List.of(List.of(box("b1"))));
    }

    @Override
    public List<? extends Shape> shapes1() {
        return List.of(circle("c1"), square("s1"));
    }

    @Override
    public List<? extends List<? extends Shape>> shapes2() {
        return List.of(List.of(circle("c1")), List.of(square("s1")));
    }

    @Override
    public List<? extends List<? extends List<? extends Shape>>> shapes3() {
        return List.of(List.of(List.of(circle("c1"), square("s1"))));
    }
}
