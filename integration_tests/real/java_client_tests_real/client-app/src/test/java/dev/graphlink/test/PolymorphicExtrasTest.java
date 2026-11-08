package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.Basket;
import dev.graphlink.test.generated.inputs.InnerInput;
import dev.graphlink.test.generated.inputs.Pet;
import dev.graphlink.test.generated.inputs.Pick;
import dev.graphlink.test.generated.interfaces.Attachment;
import dev.graphlink.test.generated.interfaces.Entity;
import dev.graphlink.test.generated.interfaces.Moment;
import dev.graphlink.test.generated.interfaces.Timed;
import dev.graphlink.test.generated.types.*;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class PolymorphicExtrasTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    private static List<String> names(List<?> values) {
        return values.stream().map(v -> v == null ? null : v.getClass().getSimpleName()).collect(Collectors.toList());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object value) {
        return (Map<String, Object>) value;
    }

    @SuppressWarnings("unchecked")
    private static List<Object> list(Object value) {
        return (List<Object>) value;
    }

    // ── nested lists of polymorphic types ───────────────────────────────────

    @Test
    void listsOfListsOfUnionsAndInterfaces() {
        Grid grid = client.queries.grid(null).getGrid();
        assertEquals(List.of(Arrays.asList("Photo", null), List.of("Video"), List.<String>of()),
            grid.getCells().stream().map(PolymorphicExtrasTest::names).collect(Collectors.toList()));
        assertEquals(List.of(List.of("Article", "Comment"), List.of("Article")),
            grid.getRows().stream().map(PolymorphicExtrasTest::names).collect(Collectors.toList()));
        assertEquals(List.of("Photo", "Document"), names(grid.getMaybe().get(0)));
    }

    @Test
    void emptyAndNullListsStayAsTheyAre() {
        Grid grid = client.queries.grid(true).getGrid();
        assertTrue(grid.getCells().isEmpty());
        assertTrue(grid.getRows().isEmpty());
        assertNull(grid.getMaybe());
    }

    @Test
    void aProjectedSelectionOfNestedLists() {
        Map<String, Object> grid = client.queries.gridProjected(null).getGrid().toJson();
        List<Object> cells = list(grid.get("cells"));
        assertEquals(640, map(list(cells.get(0)).get(0)).get("width"));
        assertNull(list(cells.get(0)).get(1));
        assertEquals(30, map(list(cells.get(1)).get(0)).get("seconds"));
        assertTrue(list(cells.get(2)).isEmpty());
        List<Object> rows = list(list(grid.get("rows")).get(0));
        assertEquals("a1", map(rows.get(0)).get("id"));
        assertEquals("Hello", map(rows.get(0)).get("title"));
        assertEquals("Nice", map(rows.get(1)).get("text"));
        List<Object> maybe = list(list(grid.get("maybe")).get(0));
        assertEquals("http://cdn/1.png", map(maybe.get(0)).get("url"));
        assertEquals("d1", map(maybe.get(1)).get("id"));
    }

    // ── custom scalars inside polymorphic types ─────────────────────────────

    @Test
    void aListOfAUnionWithScalarFields() {
        List<Moment> moments = client.queries.moments().getMoments();
        Stamp stamp = (Stamp) moments.get(0);
        assertEquals("2026-01-02T03:04:05Z", stamp.getAt());
        assertEquals(4294967296L, stamp.getBig());
        Span span = (Span) moments.get(1);
        assertEquals("2026-02-04", span.getUntil());
        assertEquals("opaque:o-9", span.getOpaque());
        assertEquals(List.of("2026-03-04T05:06:07Z"), span.getDts());
    }

    @Test
    void aListOfAnInterfaceWithScalarFields() {
        List<Timed> timed = client.queries.timed().getTimed();
        assertEquals(List.of("Span", "Stamp"), names(timed));
        assertEquals("opaque:o-9", ((Span) timed.get(0)).getOpaque());
        assertEquals(4294967296L, ((Stamp) timed.get(1)).getBig());
    }

    @Test
    void aProjectedUnionKeepsTheScalarsItSelects() {
        List<Map<String, Object>> moments = client.queries.momentsProjected().getMoments().stream()
            .map(m -> m.toJson()).collect(Collectors.toList());
        assertEquals("2026-01-02T03:04:05Z", moments.get(0).get("at"));
        assertEquals(4294967296L, ((Number) moments.get(0).get("big")).longValue());
        assertEquals("o-9", moments.get(1).get("opaque"));
        assertEquals("2026-02-04", moments.get(1).get("until"));
    }

    @Test
    void anInterfaceSelectionSharesTheInterfaceScalar() {
        List<Map<String, Object>> timed = client.queries.timedProjected().getTimed().stream()
            .map(t -> t.toJson()).collect(Collectors.toList());
        assertEquals(List.of("2026-02-03T04:05:06Z", "2026-01-02T03:04:05Z"),
            timed.stream().map(t -> t.get("at")).collect(Collectors.toList()));
        assertEquals("o-9", timed.get(0).get("opaque"));
        assertEquals(4294967296L, ((Number) timed.get(1).get("big")).longValue());
    }

    // ── a union member that points back at its union ────────────────────────

    @Test
    void aChainThreeLevelsDeep() {
        Map<String, Object> chain = client.queries.chainDeep("l1").getChain().toJson();
        assertEquals("l1", chain.get("id"));
        assertEquals("l2", map(chain.get("next")).get("id"));
        assertEquals("e1", map(map(chain.get("next")).get("next")).get("id"));
        assertEquals("done", map(map(chain.get("next")).get("next")).get("reason"));
    }

    @Test
    void theEndOfTheChainDirectlyAndAnUnknownId() {
        assertEquals("done", client.queries.chainDeep("e1").getChain().toJson().get("reason"));
        assertNull(client.queries.chainDeep("nope").getChain());
    }

    @Test
    void theAllFieldsSelectionStopsAfterOneLevel() {
        Map<String, Object> chain = client.queries.chain("l1").getChain().toJson();
        assertEquals("l1", chain.get("id"));
        assertEquals("l2", map(chain.get("next")).get("id"));
    }

    // ── lists of unions and interfaces in every operation kind ──────────────

    private int cachedVideoSeconds() {
        return ((Video) client.queries.cachedAttachments().getCachedAttachments().get(1)).getSeconds();
    }

    @Test
    void aCachedListIsServedOnceAndFetchedAgainAfterItsTagIsEvicted() {
        List<Attachment> first = client.queries.cachedAttachments().getCachedAttachments();
        assertEquals(List.of("Photo", "Video", "Document"), names(first));
        int before = cachedVideoSeconds();
        assertEquals(before, cachedVideoSeconds());
        client.mutations.evictAttachments();
        assertNotEquals(before, cachedVideoSeconds());
    }

    @Test
    void anErrorOnAListOfUnionsThrowsAndAGoodCallStillWorks() {
        assertThrows(RuntimeException.class, () -> client.queries.failingAttachments(true));
        assertEquals(3, client.queries.failingAttachments(false).getFailingAttachments().size());
    }

    @Test
    void aMutationReturningAListOfUnions() {
        assertEquals(List.of("Photo", "Video", "Document", "Photo", "Video"),
            names(client.mutations.bulkAttachments(5).getBulkAttachments()));
        assertTrue(client.mutations.bulkAttachments(0).getBulkAttachments().isEmpty());
    }

    @Test
    void aMutationReturningAListOfAnInterface() {
        List<Entity> entities = client.mutations.bulkEntities().getBulkEntities();
        assertEquals(List.of("Article", "Comment", "Article"), names(entities));
    }

    // ── @oneOf inputs with richer members ───────────────────────────────────

    private String pick(Pick pick) {
        return client.queries.describePick(pick).getDescribePick();
    }

    @Test
    void oneOfWithAnInputObject() {
        assertEquals("{inner={label=x, n=5, tags=[t]}}",
            pick(Pick.builder().inner(new InnerInput(5, "x", List.of("t"))).build()));
    }

    @Test
    void oneOfWithAnEnum() {
        assertEquals("{status=SUSPENDED}", pick(Pick.builder().status(UserStatus.SUSPENDED).build()));
    }

    @Test
    void oneOfWithAListIncludingAnEmptyOne() {
        assertEquals("{ids=[1, 2]}", pick(Pick.builder().ids(List.of(1, 2)).build()));
        assertEquals("{ids=[]}", pick(Pick.builder().ids(List.of()).build()));
    }

    @Test
    void oneOfWithAnotherOneOf() {
        assertEquals("{pet={cat=Tom}}", pick(Pick.builder().pet(new Pet("Tom", null)).build()));
    }

    @Test
    void oneOfNestedInItself() {
        Pick deep = Pick.builder().child(Pick.builder().child(Pick.builder().pet(new Pet(null, 3)).build()).build()).build();
        assertEquals("{child={child={pet={dog=3}}}}", pick(deep));
    }

    @Test
    void aListOfOneOfInputsInsideARegularInput() {
        List<Pet> pets = List.of(new Pet("a", null), new Pet(null, 2));
        assertEquals("{lead={dog=3}, pets=[{cat=a}, {dog=2}]}",
            client.queries.describeBasket(new Basket(pets, new Pet(null, 3))).getDescribeBasket());
        assertEquals("{pets=[{cat=a}, {dog=2}]}", client.queries.describeBasket(new Basket(pets, null)).getDescribeBasket());
        assertEquals("{pets=[]}", client.queries.describeBasket(new Basket(List.of(), null)).getDescribeBasket());
    }
}
