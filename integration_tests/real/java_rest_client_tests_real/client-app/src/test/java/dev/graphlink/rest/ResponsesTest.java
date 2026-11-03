package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.enums.Status;
import dev.graphlink.rest.generated.interfaces.Pet;
import dev.graphlink.rest.generated.types.Cat;
import dev.graphlink.rest.generated.types.Dog;
import dev.graphlink.rest.generated.types.Owner;
import dev.graphlink.rest.generated.types.Product;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ResponsesTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    @Test
    void okStatusesDecode() {
        assertEquals("Pen", client.queries.status(200).getName());
        assertEquals("p1", client.queries.status(201).getId());
    }

    @Test
    void noContentIsNullOrADecodeError() {
        assertNull(client.queries.status(204));
        assertThrows(IllegalStateException.class, () -> client.queries.statusNonNull(204));
    }

    @Test
    void errorStatusesRaiseRestError() {
        for (int code : new int[] {400, 401, 403, 404, 409, 422, 500, 502, 503}) {
            RestError error = assertThrows(RestError.class, () -> client.queries.status(code));
            assertEquals(code, error.getStatus());
            assertTrue(error.getBody().contains("status " + code));
            assertEquals("reason-" + code, error.getHeaders().get("x-reason"));
        }
        RestError teapot = assertThrows(RestError.class, () -> client.queries.status(418));
        assertTrue(teapot.toString().contains("418"));
        assertEquals("p1", client.queries.status(200).getId());
    }

    @Test
    void emptyBodies() {
        assertNull(client.queries.blank());
        assertThrows(IllegalStateException.class, () -> client.queries.blankNonNull());
        assertNull(client.queries.noContent());
        assertNull(client.queries.textOptional());
        assertNull(client.queries.jsonNull());
    }

    @Test
    void valueKinds() {
        assertEquals(7, client.queries.count());
        assertEquals(true, client.queries.flag());
        assertEquals("héllo ✓", client.queries.text());
        assertEquals(List.of(1, 2, 3), client.queries.deep());
        assertEquals(List.of("p1", "p2"), client.queries.wrapped().stream().map(Product::getId).collect(Collectors.toList()));
        Product unicode = client.queries.unicode();
        assertEquals("é漢😀 \"quoted\"", unicode.getName());
        assertEquals(List.of("ß"), unicode.getTags());
        Product extra = client.queries.extraKeys();
        assertEquals("x", extra.getId());
        assertNull(extra.getTags());
    }

    @Test
    void missingNonNullFieldIsANamedError() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class, () -> client.queries.missingField());
        assertEquals("Product.name is missing or null in the response", error.getMessage());
    }

    @Test
    void nestedTypesEnumsAndCycles() {
        Product p = client.queries.product("p1");
        assertEquals(Status.ACTIVE, p.getStatus());
        assertEquals("Book", p.getRelated().get(0).getName());
        assertEquals(1, p.getRelated().size());
        assertNull(p.getRelated().get(0).getRelated());
    }

    @Test
    void interfacesAndUnionsDecodeThroughTheirDiscriminator() {
        List<Pet> pets = client.queries.pets();
        assertInstanceOf(Dog.class, pets.get(0));
        assertTrue(((Dog) pets.get(0)).getBarks());
        assertInstanceOf(Cat.class, pets.get(1));
        assertEquals(9, ((Cat) pets.get(1)).getLives());
        Pet pet = client.queries.pet("c1");
        assertInstanceOf(Cat.class, pet);
        assertEquals("Tom", ((Cat) pet).getName());
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class, () -> client.queries.petsUnknown());
        assertTrue(error.getMessage().contains("bird"));
        var hits = client.queries.hits();
        assertInstanceOf(Product.class, hits.get(0));
        assertInstanceOf(Owner.class, hits.get(1));
    }

    @Test
    void graphQlAndRestShareOneClient() {
        assertEquals(19, client.queries.getCount().getGetCount());
        assertEquals(7, client.queries.count());
        assertEquals(19, client.queries.getCount().getGetCount());
    }

    @Test
    void downloads() throws Exception {
        GLDownload d = client.queries.blob(100000);
        assertEquals("blob-100000.bin", d.getFilename());
        assertTrue(d.getContentType().startsWith("application/octet-stream"));
        assertEquals(100000L, d.getLength());
        assertArrayEquals(pattern(100000), d.bytes());

        GLDownload big = client.queries.blob(8 * 1024 * 1024);
        byte[] buffer = new byte[65536];
        int received = 0;
        int reads = 0;
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream s = big.getStream()) {
            while (true) {
                int n = s.read(buffer);
                if (n < 0) break;
                received += n;
                reads++;
                digest.update(buffer, 0, n);
            }
        }
        assertEquals(8 * 1024 * 1024, received);
        assertTrue(reads > 1);
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format("%02x", b));
        assertEquals(sha256Of(pattern(8 * 1024 * 1024)), hex.toString());

        List<long[]> reports = new ArrayList<>();
        client.queries.blob(500000, (r, t) -> reports.add(new long[] {r, t})).bytes();
        assertArrayEquals(new long[] {500000L, 500000L}, reports.get(reports.size() - 1));
        for (int i = 1; i < reports.size(); i++) assertTrue(reports.get(i)[0] >= reports.get(i - 1)[0]);
        assertEquals(0, client.queries.blob(0).bytes().length);
    }

    @Test
    void missingDownloadAndRoundTrip() {
        assertEquals(404, assertThrows(RestError.class, () -> client.queries.avatar("p1")).getStatus());
        byte[] bytes = pattern(70000);
        client.mutations.uploadAvatar("p1", uploadOf(bytes, null, "image/png", true));
        GLDownload d = client.queries.avatar("p1");
        assertTrue(d.getContentType().startsWith("image/png"));
        assertEquals("p1.png", d.getFilename());
        assertArrayEquals(bytes, d.bytes());
    }

    @Test
    void nullableDownloadIsNullOnNoContent() {
        assertNull(client.queries.avatarOrEmpty("p1"));
        client.mutations.uploadAvatar("p1", uploadOf(pattern(10)));
        assertArrayEquals(pattern(10), client.queries.avatarOrEmpty("p1").bytes());
    }
}
