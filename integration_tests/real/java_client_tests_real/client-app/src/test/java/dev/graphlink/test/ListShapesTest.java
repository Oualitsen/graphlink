package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.*;
import dev.graphlink.test.generated.inputs.ListsInput;
import dev.graphlink.test.generated.types.*;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ListShapesTest {

    private static final List<Spelling> KNOWN = Arrays.stream(Spelling.values())
        .filter(v -> v != Spelling.unknownValue__)
        .collect(Collectors.toList());

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    private ListShapes shapes(String mode) {
        return client.queries.listShapes(mode).getListShapes();
    }

    private static <T> List<String> kinds(List<T> values) {
        return values.stream().map(v -> v == null ? null : v.getClass().getSimpleName()).collect(Collectors.toList());
    }

    @Test
    void scalarsWithNulls() {
        ListShapes s = shapes("full");
        assertEquals(List.of(1, 2, 3), s.getA());
        assertEquals(List.of(1, 2, 3), s.getB());
        assertEquals(Arrays.asList(1, null, 3), s.getC());
        assertEquals(Collections.singletonList(null), s.getD());
    }

    @Test
    void nestedLists() {
        ListShapes s = shapes("full");
        assertEquals(List.of(List.of(1, 2), List.of(3)), s.getE());
        assertEquals(Arrays.asList(Arrays.asList(1, null), null), s.getF());
    }

    @Test
    void enumsWithNulls() {
        assertEquals(Arrays.asList(Spelling.A, null, Spelling.B2), shapes("full").getG());
    }

    @Test
    void objectsUnionsAndInterfaces() {
        ListShapes s = shapes("full");
        assertEquals(2, s.getH().size());
        assertEquals(640, s.getH().get(0).getWidth());
        assertNull(s.getH().get(1));
        assertEquals(Arrays.asList("Photo", null, "Video"), kinds(s.getI()));
        assertEquals(Arrays.asList("Comment", null), kinds(s.getJ()));
    }

    @Test
    void emptyListsStayEmpty() {
        ListShapes s = shapes("empty");
        assertEquals(List.of(), s.getB());
        assertEquals(List.of(), s.getD());
        assertEquals(List.of(), s.getF());
        assertEquals(List.of(), s.getE());
    }

    @Test
    void nullListsStayNullWhileRequiredOnesAreEmpty() {
        ListShapes s = shapes("null");
        assertNull(s.getB());
        assertNull(s.getD());
        assertNull(s.getF());
        assertTrue(s.getA().isEmpty() && s.getG().isEmpty() && s.getI().isEmpty());
    }

    @Test
    void listArgumentsRoundTrip() {
        EchoArgsResponse res = client.queries.echoArgs(
            List.of(1, 2), Arrays.asList(1, null), List.of(List.of(1), List.of(), List.of(2, 3)),
            List.of(Spelling.X_Y, Spelling.HTTP2_OK), Arrays.asList(null, Spelling.V1), null, null);
        ListsEcho r = res.getEchoArgs();
        assertEquals(List.of(1, 2), r.getA());
        assertEquals(Arrays.asList(1, null), r.getB());
        assertEquals(List.of(List.of(1), List.of(), List.of(2, 3)), r.getC());
        assertEquals(List.of(Spelling.X_Y, Spelling.HTTP2_OK), r.getE());
        assertEquals(Arrays.asList(null, Spelling.V1), r.getF());
    }

    @Test
    void omittedListsAreNullAndDefaultsApply() {
        ListsEcho r = client.queries.echoArgs(List.of(), null, null, List.of(), null, null, null).getEchoArgs();
        assertNull(r.getB());
        assertNull(r.getC());
        assertNull(r.getF());
        assertEquals(List.of(Spelling.A, Spelling.B2), r.getG());
        assertEquals(OnlyOne.ONLY, r.getOne());
    }

    @Test
    void explicitlyEmptyDefaultBearingListIsKept() {
        ListsEcho r = client.queries.echoArgs(List.of(), null, null, List.of(), null, List.of(), null).getEchoArgs();
        assertEquals(List.of(), r.getG());
    }

    @Test
    void listInputFieldsRoundTrip() {
        ListsInput input = new ListsInput(
            List.of(3, 4), Arrays.asList(null, 5), List.of(List.of(1, 2), List.of()),
            List.of(Spelling.SNAKE_CASE_2), Arrays.asList(Spelling.A, null), List.of(Spelling.V1), null);
        ListsEcho r = client.queries.echoInput(input).getEchoInput();
        assertEquals(List.of(3, 4), r.getA());
        assertEquals(Arrays.asList(null, 5), r.getB());
        assertEquals(List.of(List.of(1, 2), List.of()), r.getC());
        assertEquals(List.of(Spelling.SNAKE_CASE_2), r.getE());
        assertEquals(Arrays.asList(Spelling.A, null), r.getF());
        assertEquals(List.of(Spelling.V1), r.getG());
    }

    @Test
    void inputDefaultsReachTheServer() {
        ListsEcho r = client.queries.echoInput(new ListsInput(List.of(), null, null, List.of(), null, null, null)).getEchoInput();
        assertEquals(List.of(Spelling.A, Spelling.B2), r.getG());
        assertEquals(OnlyOne.ONLY, r.getOne());
    }

    @Test
    void largeListOfScalars() {
        List<Integer> r = client.queries.bigInts(50000).getBigInts();
        assertEquals(50000, r.size());
        assertEquals(49999, r.get(49999));
    }

    @Test
    void largeListOfObjects() {
        List<Photo> r = client.queries.bigPhotos(20000).getBigPhotos();
        assertEquals(20000, r.size());
        assertEquals("p19999", r.get(19999).getId());
        assertEquals(19999, r.get(19999).getWidth());
    }

    @Test
    void everySpellingRoundTrips() {
        assertEquals(KNOWN, client.queries.echoArgs(List.of(), null, null, KNOWN, null, null, null).getEchoArgs().getE());
    }

    @Test
    void wireNamesAreTheDeclaredOnes() {
        assertEquals(
            List.of("A", "B2", "x__y", "http2_ok", "v1", "snake_case_2"),
            KNOWN.stream().map(Spelling::toJson).collect(Collectors.toList()));
    }

    @Test
    void enumUsedOnlyAsArgument() {
        assertEquals("P2", client.queries.argOnly(ArgOnly.P2).getArgOnly());
    }

    @Test
    void enumUsedOnlyInResponse() {
        assertEquals(RespOnly.R2, client.queries.respOnly().getRespOnly());
    }

    @Test
    void unknownEnumValueInAField() {
        PhaseProbe p = client.queries.phaseProbe().getPhaseProbe();
        assertEquals(Phase.unknownValue__, p.getSingle());
        assertEquals(Phase.unknownValue__, p.getMaybe());
    }

    @Test
    void unknownEnumValueInListElements() {
        PhaseProbe p = client.queries.phaseProbe().getPhaseProbe();
        assertEquals(List.of(Phase.OPEN, Phase.unknownValue__, Phase.CLOSED), p.getList());
        assertEquals(Arrays.asList(Phase.unknownValue__, null), p.getNullableList());
    }

    @Test
    void unknownEnumValueInAUnionMember() {
        Object h = client.queries.phaseHolder().getPhaseHolder();
        assertEquals(Phase.unknownValue__, ((Phased) h).getPhase());
    }
}
