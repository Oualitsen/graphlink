package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.rest.GraphLinkDownload;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.InputStreamResource;
import java.nio.charset.StandardCharsets;
import dev.graphlink.javaserver.generated.enums.RestColor;
import dev.graphlink.javaserver.generated.inputs.RestAddress;
import dev.graphlink.javaserver.generated.inputs.RestFilter;
import dev.graphlink.javaserver.generated.inputs.RestLine;
import dev.graphlink.javaserver.generated.inputs.RestPerson;
import dev.graphlink.javaserver.generated.inputs.RestItemInput;
import dev.graphlink.javaserver.generated.inputs.RestMeta;
import dev.graphlink.javaserver.generated.services.*;
import dev.graphlink.javaserver.generated.types.*;
import graphql.GraphQLContext;
import org.springframework.stereotype.Service;

import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

final class RestFixtures {
    private RestFixtures() {}

    static RestItem item(String id, String name, int qty, RestColor color, List<String> tags) {
        return RestItem.builder().id(id).name(name).qty(qty).color(color).tags(tags == null ? List.of() : tags).build();
    }

    static RestItem fromInput(String id, RestItemInput input) {
        return item(id, input.getName(), input.getQty(), input.getColor(), input.getTags());
    }
}

@Service
class RestItemServiceImpl implements RestItemService {
    @Override
    public RestItem restItem(String id) {
        return "missing".equals(id) ? null : RestFixtures.item(id, "item-" + id, 1, null, null);
    }

    @Override
    public RestItem restItemByColor(RestColor color) {
        return RestFixtures.item(color.toJson().toLowerCase(), "color-" + color.toJson(), 1, color, List.of(color.toJson().toLowerCase()));
    }

    @Override
    public RestItem restItemGraphql(String id) {
        return restItem(id);
    }

    @Override
    public RestItem restCreate(RestItemInput input) {
        return RestFixtures.fromInput("new-" + input.getName(), input);
    }

    @Override
    public RestItem restReplace(String id, RestItemInput input) {
        return RestFixtures.fromInput(id, input);
    }

    @Override
    public RestItem restPatch(String id, String name) {
        return RestFixtures.item(id, name == null ? "item-" + id : name, 1, null, null);
    }

    @Override
    public List<RestItem> restBulk(List<RestItemInput> items) {
        List<RestItem> result = new ArrayList<>();
        for (int i = 0; i < items.size(); i++) {
            result.add(RestFixtures.fromInput("bulk-" + i, items.get(i)));
        }
        return result;
    }
}

@Service
class RestScalarsServiceImpl implements RestScalarsService {
    @Override
    public RestScalars restScalars(int n, double ratio, boolean flag, String text) {
        return RestScalars.builder().n(n).ratio(ratio).flag(flag).text(text).build();
    }

    @Override
    public RestScalars restFail(int code) {
        throw new IllegalStateException("boom " + code);
    }
}

@Service
class RestSearchServiceImpl implements RestSearchService {
    @Override
    public RestSearch restSearch(RestFilter filter, Integer limit, Integer offset, RestColor order) {
        RestSearch.Builder result = RestSearch.builder().limit(limit == null ? 10 : limit).offset(offset).order(order);
        if (filter != null) {
            result.tag(filter.getTag()).minQty(filter.getMinQty()).maxPrice(filter.getMaxPrice())
                    .colors(filter.getColors()).inStock(filter.getInStock());
        }
        return result.build();
    }
}

@Service
class RestTagsServiceImpl implements RestTagsService {
    @Override
    public List<String> restTags(List<String> tags, List<Integer> ids) {
        List<String> result = new ArrayList<>(tags);
        if (ids != null) {
            ids.forEach(id -> result.add("#" + id));
        }
        return result;
    }
}

@Service
class RestGreetingServiceImpl implements RestGreetingService {
    @Override
    public String restGreeting(String name) {
        return "hello " + name;
    }
}

@Service
class RestPlainServiceImpl implements RestPlainService {
    @Override
    public String restPlain(String name) {
        return "plain " + name;
    }
}

@Service
class RestCountServiceImpl implements RestCountService {
    @Override
    public int restCount() {
        return 42;
    }
}

@Service
class RestFlagServiceImpl implements RestFlagService {
    @Override
    public boolean restFlag(boolean on) {
        return !on;
    }
}

@Service
class RestColorsServiceImpl implements RestColorsService {
    @Override
    public List<RestColor> restColors() {
        return List.of(RestColor.RED, RestColor.GREEN, RestColor.BLUE);
    }
}

@Service
class RestHeadersServiceImpl implements RestHeadersService {
    @Override
    public RestHeaders restHeaders(String token, String trace, RestMeta meta) {
        RestHeaders.Builder result = RestHeaders.builder().token(token).trace(trace);
        if (meta != null) {
            result.traceId(meta.getTraceId()).version(meta.getVersion());
        }
        return result.build();
    }
}

@Service
class RestDeleteServiceImpl implements RestDeleteService {
    @Override
    public Void restDelete(String id) {
        return null;
    }
}

@Service
class RestOptionalBodyServiceImpl implements RestOptionalBodyService {
    @Override
    public int restOptionalBody(RestItemInput input) {
        return input == null ? -1 : input.getQty();
    }
}

@Service
class RestValidatedServiceImpl implements RestValidatedService {
    @Override
    public boolean restValidated(String name) {
        return true;
    }

    @Override
    public void validateRestValidated(String name) {
        if ("invalid".equals(name)) {
            throw new IllegalArgumentException("invalid name");
        }
    }
}

@Service
class RestKeywordsServiceImpl implements RestKeywordsService {
    @Override
    public RestKeywords restKeywords(String switch_, String class_, String return_, int if_) {
        return RestKeywords.builder().class_(class_).return_(return_).if_(if_).switch_(switch_).build();
    }
}

final class RestUploads {
    private RestUploads() {}

    static RestUploadInfo info(MultipartFile file, String label, RestColor kind, Integer times) {
        try (InputStream in = file.getInputStream()) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[8192];
            long size = 0;
            int read;
            while ((read = in.read(buffer)) > 0) {
                digest.update(buffer, 0, read);
                size += read;
            }
            String filename = file.getOriginalFilename();
            return RestUploadInfo.builder()
                    .filename(filename == null || filename.isEmpty() ? null : filename)
                    .contentType(file.getContentType())
                    .size((int) size)
                    .sha256(HexFormat.of().formatHex(digest.digest()))
                    .label(label)
                    .kind(kind)
                    .times(times)
                    .build();
        } catch (IOException | NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}

@Service
class RestUploadInfoServiceImpl implements RestUploadInfoService {
    @Override
    public RestUploadInfo restUpload(String label, RestColor kind, Integer times, MultipartFile file) {
        return RestUploads.info(file, label, kind, times);
    }

    @Override
    public List<RestUploadInfo> restUploadMany(String label, List<MultipartFile> files) {
        List<RestUploadInfo> result = new ArrayList<>();
        for (MultipartFile file : files) {
            result.add(RestUploads.info(file, label, null, null));
        }
        return result;
    }

    @Override
    public RestUploadInfo restUploadRaw(String id, String name, MultipartFile file) {
        return RestUploads.info(file, name, null, null);
    }
}

@Service
class RestUploadOptionalServiceImpl implements RestUploadOptionalService {
    @Override
    public int restUploadOptional(MultipartFile file) {
        return file == null ? -1 : (int) file.getSize();
    }
}

@Service
class RestFormEchoServiceImpl implements RestFormEchoService {
    @Override
    public RestFormEcho restForm(String name, int qty, RestColor color, Boolean flag, List<String> tags, String note) {
        return RestFormEcho.builder()
                .name(name).qty(qty).color(color).flag(flag).tags(tags == null ? List.of() : tags).note(note).build();
    }

    @Override
    public RestFormEcho restFormUpdate(String id, String name, Integer qty) {
        return RestFormEcho.builder().id(id).name(name).qty(qty).flag(false).tags(List.of()).build();
    }
}

@Service
class RestFormOptionalServiceImpl implements RestFormOptionalService {
    @Override
    public int restFormOptional(String note) {
        return note == null ? -1 : note.length();
    }
}

@Service
class RestMarkedServiceImpl implements RestMarkedService {
    private static RestMarked marked(String name, GraphQLContext context) {
        return RestMarked.builder().name(name).marker(context == null ? null : context.get("marker")).hasContext(context != null).build();
    }

    @Override
    public RestMarked restIntercepted(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public RestMarked restInjected(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public RestMarked restUnguarded(String name) {
        return marked(name, null);
    }

    @Override
    public RestMarked restBlockGuarded(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public RestMarked restInterceptedBody(RestItemInput input, GraphQLContext graphQLContext) {
        return marked(input.getName(), graphQLContext);
    }
}

@Service
class RestInterceptedVoidServiceImpl implements RestInterceptedVoidService {
    @Override
    public Void restInterceptedVoid(String name, GraphQLContext graphQLContext) {
        return null;
    }
}

final class RestDownloads {
    private RestDownloads() {}

    static GraphLinkDownload make(String name, String kind) {
        if ("bin".equals(kind)) {
            return new GraphLinkDownload(new ByteArrayResource(pattern(1000)), "data.bin", null);
        }
        if ("nofile".equals(kind)) {
            return GraphLinkDownload.of(new ByteArrayResource("x".getBytes(StandardCharsets.UTF_8)));
        }
        if ("type".equals(kind)) {
            return new GraphLinkDownload(new ByteArrayResource("{\"a\":1}".getBytes(StandardCharsets.UTF_8)), null, "application/json");
        }
        return new GraphLinkDownload(
                new ByteArrayResource(("hello " + name).getBytes(StandardCharsets.UTF_8)), name + ".txt", "text/plain");
    }

    static byte[] pattern(int size) {
        byte[] bytes = new byte[size];
        for (int i = 0; i < size; i++) {
            bytes[i] = (byte) (i % 251);
        }
        return bytes;
    }

    static GraphLinkDownload large(int size) {
        InputStream stream = new InputStream() {
            private long position = 0;

            @Override
            public int read() {
                return position < size ? (int) (position++ % 251) : -1;
            }

            @Override
            public int read(byte[] buffer, int offset, int length) {
                if (position >= size) {
                    return -1;
                }
                int count = (int) Math.min(length, size - position);
                for (int i = 0; i < count; i++) {
                    buffer[offset + i] = (byte) ((position + i) % 251);
                }
                position += count;
                return count;
            }
        };
        return new GraphLinkDownload(new InputStreamResource(stream), "large.bin", null);
    }
}

@Service
class RestDownloadServiceImpl implements RestDownloadService {
    @Override
    public GraphLinkDownload restDownload(String name, String kind) {
        return RestDownloads.make(name, kind);
    }
}

@Service
class RestDownloadOptionalServiceImpl implements RestDownloadOptionalService {
    @Override
    public GraphLinkDownload restDownloadOptional(String name) {
        return name == null ? null : RestDownloads.make(name, null);
    }
}

@Service
class RestDownloadLargeServiceImpl implements RestDownloadLargeService {
    @Override
    public GraphLinkDownload restDownloadLarge(int size) {
        return RestDownloads.large(size);
    }
}

@Service
class RestWrapServiceImpl implements RestWrapService {
    @Override
    public RestWrap restWrapDeep(String v) {
        return RestWrap.builder().value(v).build();
    }

    @Override
    public List<RestWrap> restWrapList(int n) {
        List<RestWrap> items = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            items.add(RestWrap.builder().value("item-" + i).build());
        }
        return items;
    }

    @Override
    public RestWrap restWrapNullable(boolean on) {
        return on ? RestWrap.builder().value("on").build() : null;
    }
}

@Service
class RestWrapColorServiceImpl implements RestWrapColorService {
    @Override
    public RestColor restWrapColor() {
        return RestColor.BLUE;
    }
}

@Service
class RestWrapTextServiceImpl implements RestWrapTextService {
    @Override
    public String restWrapText(String v) {
        return "text:" + v;
    }
}

final class RestNestedSummaries {
    private RestNestedSummaries() {}

    private static String orDash(Object value) {
        return value == null ? "-" : value.toString();
    }

    static String person(RestPerson person) {
        if (person == null) {
            return "none";
        }
        RestAddress address = person.getAddress();
        String tags = person.getTags() == null ? "-" : String.join(",", person.getTags());
        return String.join("|", person.getName(), orDash(person.getAge()), address == null ? "-" : address.getCity(),
                address == null ? "-" : orDash(address.getZip()), tags, orDash(person.getKind()));
    }

    static String lines(List<RestLine> lines) {
        if (lines == null) {
            return "-";
        }
        List<String> parts = new ArrayList<>();
        for (RestLine line : lines) {
            parts.add(line.getSku() + ":" + line.getQty());
        }
        return String.join(";", parts);
    }
}

@Service
class RestNestedServiceImpl implements RestNestedService {
    @Override
    public RestNested restNestedSpread(RestPerson person) {
        return RestNested.builder().summary(RestNestedSummaries.person(person)).build();
    }

    @Override
    public RestNested restNestedSpreadOptional(RestPerson person) {
        return RestNested.builder().summary(RestNestedSummaries.person(person)).build();
    }

    @Override
    public RestNested restNestedFlat(RestPerson person) {
        return RestNested.builder().summary(RestNestedSummaries.person(person)).build();
    }

    @Override
    public RestNested restNestedLines(List<RestLine> lines) {
        return RestNested.builder().summary(RestNestedSummaries.lines(lines)).build();
    }

    @Override
    public RestNested restNestedJson(RestPerson person) {
        return RestNested.builder().summary(RestNestedSummaries.person(person)).build();
    }

    @Override
    public RestNested restNestedForm(RestPerson person, List<RestLine> lines, String note) {
        return RestNested.builder().summary(RestNestedSummaries.person(person) + "/" + RestNestedSummaries.lines(lines) + "/" + (note == null ? "-" : note)).build();
    }

    @Override
    public RestNested restNestedFormJson(RestPerson person) {
        return RestNested.builder().summary(RestNestedSummaries.person(person)).build();
    }
}
