package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.inputs.*;
import dev.graphlink.rest.generated.types.Echo;
import dev.graphlink.rest.generated.types.Part;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

class UploadsTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    private Echo multipart(String title, Meta meta, Meta asJson, GLUpload one, List<GLUpload> many) {
        return client.mutations.eMultipart(title, meta, asJson, one, many);
    }

    @Test
    void multipartHasABoundaryAndTextPartsWithoutFilename() {
        Echo e = multipart("Hello é", null, null, null, null);
        assertTrue(e.getContentType().startsWith("multipart/form-data; boundary="));
        Part title = part(e, "title");
        assertNull(title.getFilename());
        assertEquals("Hello é", title.getText());
    }

    @Test
    void fileParts() {
        byte[] bytes = pattern(70000);
        Echo e = multipart(null, null, null, uploadOf(bytes, "photo.png", "image/png", true), null);
        Part part = part(e, "one");
        assertEquals("photo.png", part.getFilename());
        assertTrue(part.getContentType().startsWith("image/png"));
        assertEquals(bytes.length, part.getSize());
        assertEquals(sha256Of(bytes), part.getSha256());
    }

    @Test
    void listOfUploadsRepeatsThePartNameInOrder() {
        List<byte[]> files = List.of(pattern(10), pattern(2000), new byte[0]);
        List<GLUpload> uploads = new ArrayList<>();
        for (int i = 0; i < files.size(); i++) uploads.add(uploadOf(files.get(i), "f" + i + ".bin"));
        List<Part> parts = partsNamed(multipart(null, null, null, null, uploads), "many");
        assertEquals(List.of("f0.bin", "f1.bin", "f2.bin"), parts.stream().map(Part::getFilename).collect(Collectors.toList()));
        assertEquals(List.of(10, 2000, 0), parts.stream().map(Part::getSize).collect(Collectors.toList()));
        assertEquals(files.stream().map(Support::sha256Of).collect(Collectors.toList()), parts.stream().map(Part::getSha256).collect(Collectors.toList()));
    }

    @Test
    void unknownLengthAndNonAsciiFilename() {
        byte[] bytes = pattern(300000);
        assertEquals(sha256Of(bytes), part(multipart(null, null, null, uploadOf(bytes, "u.bin", "application/octet-stream", false), null), "one").getSha256());
        String name = part(multipart(null, null, null, uploadOf(pattern(3), "é漢.png"), null), "one").getFilename();
        assertTrue(name.equals("é漢.png") || name.equals(GraphLinkRestUtils.restEncode("é漢.png")));
    }

    @Test
    @SuppressWarnings("unchecked")
    void objectAndJsonParts() {
        Echo e = multipart(null, new Meta("m", List.of("a", "b"), new Address("Oran", null, null)), null, null, null);
        assertEquals("m", part(e, "meta.name").getText());
        assertEquals(List.of("a", "b"), partsNamed(e, "meta.tags").stream().map(Part::getText).collect(Collectors.toList()));
        assertEquals("Oran", part(e, "meta.address.city").getText());
        Part json = part(multipart(null, null, new Meta("m", null, null), null, null), "j");
        assertTrue(json.getContentType().startsWith("application/json"));
        assertEquals("m", ((Map<String, Object>) parseJson(json.getText())).get("name"));
    }

    @Test
    void partsTravelTogetherAndNothingMeansNoBody() {
        byte[] bytes = pattern(1000);
        Echo e = multipart("t", null, new Meta("m", null, null), uploadOf(bytes, "a.bin"), List.of(uploadOf(bytes, "b.bin"), uploadOf(bytes, "c.bin")));
        assertEquals(List.of("title", "j", "one", "many", "many"), e.getParts().stream().map(Part::getName).collect(Collectors.toList()));
        Echo empty = multipart(null, null, null, null, null);
        assertEquals(0, empty.getBodySize());
        assertNull(empty.getContentType());
    }

    @Test
    void multipartProgressEndsAtTheTotal() {
        byte[] bytes = pattern(1500000);
        List<long[]> reports = new ArrayList<>();
        Echo e = client.mutations.eMultipart(null, null, null, uploadOf(bytes, "big.bin"), null, (sent, total) -> reports.add(new long[] {sent, total}));
        assertEquals(sha256Of(bytes), part(e, "one").getSha256());
        assertFalse(reports.isEmpty());
        for (int i = 1; i < reports.size(); i++) assertTrue(reports.get(i)[0] >= reports.get(i - 1)[0]);
        long[] last = reports.get(reports.size() - 1);
        assertEquals(last[1], last[0]);
        assertTrue(last[1] > bytes.length);
    }

    @Test
    void multipartStreamsWithAndWithoutALength() {
        byte[] bytes = pattern(300000);
        Echo known = multipart(null, null, null, uploadOf(bytes, "k.bin"), null);
        assertNotNull(known.getContentLength());
        assertFalse(known.getChunked());
        Echo unknown = multipart(null, null, null, uploadOf(bytes, "u.bin", "application/octet-stream", false), null);
        assertTrue(unknown.getChunked());
        assertNull(unknown.getContentLength());
        assertEquals(sha256Of(bytes), part(unknown, "one").getSha256());
    }

    @Test
    void rawBodyIsExactlyTheFileBytes() {
        byte[] bytes = pattern(120000);
        Echo e = client.mutations.eRaw(uploadOf(bytes, null, "image/png", true));
        assertEquals("PUT", e.getMethod());
        assertTrue(e.getContentType().startsWith("image/png"));
        assertEquals(bytes.length, e.getBodySize());
        assertEquals(sha256Of(bytes), e.getBodySha256());
        assertEquals(bytes.length, e.getContentLength());
        assertFalse(e.getChunked());
    }

    @Test
    void unknownLengthRawUploadIsChunked() {
        byte[] bytes = pattern(250000);
        Echo e = client.mutations.eRaw(uploadOf(bytes, null, "application/octet-stream", false));
        assertTrue(e.getChunked());
        assertNull(e.getContentLength());
        assertEquals(sha256Of(bytes), e.getBodySha256());
    }

    @Test
    void rawMimeTypeAndOptionalBodies() {
        assertTrue(client.mutations.eRaw(uploadOf(pattern(5))).getContentType().startsWith("application/octet-stream"));
        assertTrue(client.mutations.eRawType(uploadOf(pattern(5), null, "image/png", true)).getContentType().startsWith("application/x-custom"));
        assertEquals(0, client.mutations.eRaw(uploadOf(new byte[0])).getBodySize());
        Echo none = client.mutations.eRawOptional(null);
        assertEquals(0, none.getBodySize());
        assertNull(none.getContentType());
    }

    @Test
    void filenameIsNotSentOnRawUploads() {
        Echo e = client.mutations.eRaw(uploadOf(pattern(5), "secret-name.bin"));
        assertFalse(e.getHeaders().stream().map(h -> h.getValue()).collect(Collectors.joining("|")).contains("secret-name"));
        assertFalse(e.getPath().contains("secret-name"));
    }

    @Test
    void largeRawUploadProgress() {
        byte[] bytes = pattern(6 * 1024 * 1024);
        List<long[]> reports = new ArrayList<>();
        Echo e = client.mutations.eRaw(uploadOf(bytes), (s, t) -> reports.add(new long[] {s, t}));
        assertEquals(sha256Of(bytes), e.getBodySha256());
        assertArrayEquals(new long[] {bytes.length, bytes.length}, reports.get(reports.size() - 1));
        for (int i = 1; i < reports.size(); i++) assertTrue(reports.get(i)[0] >= reports.get(i - 1)[0]);
        List<long[]> unknown = new ArrayList<>();
        client.mutations.eRaw(uploadOf(pattern(40000), null, "application/octet-stream", false), (s, t) -> unknown.add(new long[] {s, t}));
        assertFalse(unknown.isEmpty());
        assertTrue(unknown.stream().allMatch(r -> r[1] == -1L || r[1] == 40000L));
        assertEquals(40000L, unknown.get(unknown.size() - 1)[0]);
    }

    @Test
    @Timeout(value = 10, unit = TimeUnit.SECONDS)
    void aFailingSourceFailsTheCallWithoutHanging() {
        assertThrows(Exception.class, () -> client.mutations.eRaw(failingUpload()));
        assertEquals("GET", client.queries.eAccept().getMethod());
    }
}
