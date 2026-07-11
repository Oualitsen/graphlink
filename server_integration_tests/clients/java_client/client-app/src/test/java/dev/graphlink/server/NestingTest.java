package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.enums.Color;
import dev.graphlink.server.generated.types.Photo;
import dev.graphlink.server.generated.types.Video;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

public class NestingTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Test
    void enumListDepths123() {
        assertEquals(List.of(Color.RED, Color.GREEN, Color.BLUE), client.queries.colors1().getColors1());
        assertEquals(
                List.of(List.of(Color.RED), List.of(Color.GREEN, Color.BLUE)),
                client.queries.colors2().getColors2());
        assertEquals(
                List.of(List.of(List.of(Color.RED))),
                client.queries.colors3().getColors3());
    }

    @Test
    void typeListDepths123() {
        var b1 = client.queries.boxes1().getBoxes1();
        assertEquals(2, b1.size());

        var b2 = client.queries.boxes2().getBoxes2();
        assertEquals(2, b2.size());

        var b3 = client.queries.boxes3().getBoxes3();
        assertEquals("b1", b3.get(0).get(0).get(0).getId());
    }

    @Test
    void interfaceListDepths123() {
        var s1 = client.queries.shapes1().getShapes1();
        var kinds = s1.stream().map(s -> s.getKind()).toList();
        assertTrue(kinds.containsAll(List.of("circle", "square")));

        var s3 = client.queries.shapes3().getShapes3();
        assertNotNull(s3.get(0).get(0).get(0).getKind());
    }

    @Test
    void unionListDepths123() {
        var m1 = client.queries.media1().getMedia1();
        assertEquals(2, m1.size());
        var photo = m1.stream().filter(Photo.class::isInstance).map(Photo.class::cast).findFirst().orElseThrow();
        assertEquals(640, photo.getWidth());
        var video = m1.stream().filter(Video.class::isInstance).map(Video.class::cast).findFirst().orElseThrow();
        assertEquals(30, video.getDurationSec());

        var m3 = client.queries.media3().getMedia3();
        assertNotNull(m3.get(0).get(0).get(0).getUrl());
    }
}
