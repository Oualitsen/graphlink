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
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.core.io.buffer.DataBufferUtils;
import org.springframework.core.io.buffer.DefaultDataBufferFactory;
import org.springframework.http.codec.multipart.FilePart;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.io.InputStream;
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
    public Mono<RestItem> restItem(String id) {
        return "missing".equals(id) ? Mono.empty() : Mono.just(RestFixtures.item(id, "item-" + id, 1, null, null));
    }

    @Override
    public Mono<RestItem> restItemByColor(RestColor color) {
        return Mono.just(RestFixtures.item(color.toJson().toLowerCase(), "color-" + color.toJson(), 1, color, List.of(color.toJson().toLowerCase())));
    }

    @Override
    public Mono<RestItem> restItemGraphql(String id) {
        return restItem(id);
    }

    @Override
    public Mono<RestItem> restCreate(RestItemInput input) {
        return Mono.just(RestFixtures.fromInput("new-" + input.getName(), input));
    }

    @Override
    public Mono<RestItem> restReplace(String id, RestItemInput input) {
        return Mono.just(RestFixtures.fromInput(id, input));
    }

    @Override
    public Mono<RestItem> restPatch(String id, String name) {
        return Mono.just(RestFixtures.item(id, name == null ? "item-" + id : name, 1, null, null));
    }

    @Override
    public Flux<RestItem> restBulk(List<RestItemInput> items) {
        List<RestItem> result = new ArrayList<>();
        for (int i = 0; i < items.size(); i++) {
            result.add(RestFixtures.fromInput("bulk-" + i, items.get(i)));
        }
        return Flux.fromIterable(result);
    }
}

@Service
class RestScalarsServiceImpl implements RestScalarsService {
    @Override
    public Mono<RestScalars> restScalars(Integer n, Double ratio, Boolean flag, String text) {
        return Mono.just(RestScalars.builder().n(n).ratio(ratio).flag(flag).text(text).build());
    }

    @Override
    public Mono<RestScalars> restFail(Integer code) {
        return Mono.error(new IllegalStateException("boom " + code));
    }
}

@Service
class RestSearchServiceImpl implements RestSearchService {
    @Override
    public Mono<RestSearch> restSearch(RestFilter filter, Integer limit, Integer offset, RestColor order) {
        RestSearch.Builder result = RestSearch.builder().limit(limit == null ? 10 : limit).offset(offset).order(order);
        if (filter != null) {
            result.tag(filter.getTag()).minQty(filter.getMinQty()).maxPrice(filter.getMaxPrice())
                    .colors(filter.getColors()).inStock(filter.getInStock());
        }
        return Mono.just(result.build());
    }
}

@Service
class RestTagsServiceImpl implements RestTagsService {
    @Override
    public Flux<String> restTags(List<String> tags, List<Integer> ids) {
        List<String> result = new ArrayList<>(tags);
        if (ids != null) {
            ids.forEach(id -> result.add("#" + id));
        }
        return Flux.fromIterable(result);
    }
}

@Service
class RestGreetingServiceImpl implements RestGreetingService {
    @Override
    public Mono<String> restGreeting(String name) {
        return Mono.just("hello " + name);
    }
}

@Service
class RestPlainServiceImpl implements RestPlainService {
    @Override
    public Mono<String> restPlain(String name) {
        return Mono.just("plain " + name);
    }
}

@Service
class RestCountServiceImpl implements RestCountService {
    @Override
    public Mono<Integer> restCount() {
        return Mono.just(42);
    }
}

@Service
class RestFlagServiceImpl implements RestFlagService {
    @Override
    public Mono<Boolean> restFlag(Boolean on) {
        return Mono.just(!on);
    }
}

@Service
class RestColorsServiceImpl implements RestColorsService {
    @Override
    public Flux<RestColor> restColors() {
        return Flux.just(RestColor.RED, RestColor.GREEN, RestColor.BLUE);
    }
}

@Service
class RestHeadersServiceImpl implements RestHeadersService {
    @Override
    public Mono<RestHeaders> restHeaders(String token, String trace, RestMeta meta) {
        RestHeaders.Builder result = RestHeaders.builder().token(token).trace(trace);
        if (meta != null) {
            result.traceId(meta.getTraceId()).version(meta.getVersion());
        }
        return Mono.just(result.build());
    }
}

@Service
class RestDeleteServiceImpl implements RestDeleteService {
    @Override
    public Mono<Void> restDelete(String id) {
        return Mono.empty();
    }
}

@Service
class RestOptionalBodyServiceImpl implements RestOptionalBodyService {
    @Override
    public Mono<Integer> restOptionalBody(RestItemInput input) {
        return Mono.just(input == null ? -1 : input.getQty());
    }
}

@Service
class RestValidatedServiceImpl implements RestValidatedService {
    @Override
    public Mono<Boolean> restValidated(String name) {
        return Mono.just(true);
    }

    @Override
    public Mono<Void> validateRestValidated(String name) {
        return "invalid".equals(name) ? Mono.error(new IllegalArgumentException("invalid name")) : Mono.empty();
    }
}

@Service
class RestKeywordsServiceImpl implements RestKeywordsService {
    @Override
    public Mono<RestKeywords> restKeywords(String switch_, String class_, String return_, Integer if_) {
        return Mono.just(RestKeywords.builder().class_(class_).return_(return_).if_(if_).switch_(switch_).build());
    }
}

final class RestUploads {
    private RestUploads() {}

    static Mono<byte[]> bytes(FilePart file) {
        return DataBufferUtils.join(file.content())
                .map(buffer -> {
                    byte[] bytes = new byte[buffer.readableByteCount()];
                    buffer.read(bytes);
                    DataBufferUtils.release(buffer);
                    return bytes;
                })
                .defaultIfEmpty(new byte[0]);
    }

    static Mono<RestUploadInfo> info(FilePart file, String label, RestColor kind, Integer times) {
        return bytes(file).map(bytes -> {
            try {
                String filename = file.filename();
                return RestUploadInfo.builder()
                        .filename(filename == null || filename.isEmpty() ? null : filename)
                        .contentType(file.headers().getContentType() == null ? null : file.headers().getContentType().toString())
                        .size(bytes.length)
                        .sha256(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)))
                        .label(label)
                        .kind(kind)
                        .times(times)
                        .build();
            } catch (NoSuchAlgorithmException e) {
                throw new IllegalStateException(e);
            }
        });
    }
}

@Service
class RestUploadInfoServiceImpl implements RestUploadInfoService {
    @Override
    public Mono<RestUploadInfo> restUpload(String label, RestColor kind, Integer times, FilePart file) {
        return RestUploads.info(file, label, kind, times);
    }

    @Override
    public Flux<RestUploadInfo> restUploadMany(String label, List<FilePart> files) {
        return Flux.fromIterable(files).concatMap(file -> RestUploads.info(file, label, null, null));
    }

    @Override
    public Mono<RestUploadInfo> restUploadRaw(String id, String name, FilePart file) {
        return RestUploads.info(file, name, null, null);
    }
}

@Service
class RestUploadOptionalServiceImpl implements RestUploadOptionalService {
    @Override
    public Mono<Integer> restUploadOptional(FilePart file) {
        return file == null ? Mono.just(-1) : RestUploads.bytes(file).map(bytes -> bytes.length);
    }
}

@Service
class RestFormEchoServiceImpl implements RestFormEchoService {
    @Override
    public Mono<RestFormEcho> restForm(String name, Integer qty, RestColor color, Boolean flag, List<String> tags, String note) {
        return Mono.just(RestFormEcho.builder()
                .name(name).qty(qty).color(color).flag(flag).tags(tags == null ? List.of() : tags).note(note).build());
    }

    @Override
    public Mono<RestFormEcho> restFormUpdate(String id, String name, Integer qty) {
        return Mono.just(RestFormEcho.builder().id(id).name(name).qty(qty).flag(false).tags(List.of()).build());
    }
}

@Service
class RestFormOptionalServiceImpl implements RestFormOptionalService {
    @Override
    public Mono<Integer> restFormOptional(String note) {
        return Mono.just(note == null ? -1 : note.length());
    }
}

@Service
class RestMarkedServiceImpl implements RestMarkedService {
    private static Mono<RestMarked> marked(String name, GraphQLContext context) {
        return Mono.just(RestMarked.builder().name(name).marker(context == null ? null : context.get("marker")).hasContext(context != null).build());
    }

    @Override
    public Mono<RestMarked> restIntercepted(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public Mono<RestMarked> restInjected(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public Mono<RestMarked> restUnguarded(String name) {
        return marked(name, null);
    }

    @Override
    public Mono<RestMarked> restBlockGuarded(String name, GraphQLContext graphQLContext) {
        return marked(name, graphQLContext);
    }

    @Override
    public Mono<RestMarked> restInterceptedBody(RestItemInput input, GraphQLContext graphQLContext) {
        return marked(input.getName(), graphQLContext);
    }
}

@Service
class RestInterceptedVoidServiceImpl implements RestInterceptedVoidService {
    @Override
    public Mono<Void> restInterceptedVoid(String name, GraphQLContext graphQLContext) {
        return Mono.empty();
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
    public Mono<GraphLinkDownload> restDownload(String name, String kind) {
        return Mono.just(RestDownloads.make(name, kind));
    }
}

@Service
class RestDownloadOptionalServiceImpl implements RestDownloadOptionalService {
    @Override
    public Mono<GraphLinkDownload> restDownloadOptional(String name) {
        return name == null ? Mono.empty() : Mono.just(RestDownloads.make(name, null));
    }
}

@Service
class RestDownloadLargeServiceImpl implements RestDownloadLargeService {
    @Override
    public Mono<GraphLinkDownload> restDownloadLarge(Integer size) {
        return Mono.just(RestDownloads.large(size));
    }
}

@Service
class RestWrapServiceImpl implements RestWrapService {
    @Override
    public Mono<RestWrap> restWrapDeep(String v) {
        return Mono.just(RestWrap.builder().value(v).build());
    }

    @Override
    public Flux<RestWrap> restWrapList(Integer n) {
        List<RestWrap> items = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            items.add(RestWrap.builder().value("item-" + i).build());
        }
        return Flux.fromIterable(items);
    }

    @Override
    public Mono<RestWrap> restWrapNullable(Boolean on) {
        return on ? Mono.just(RestWrap.builder().value("on").build()) : Mono.empty();
    }
}

@Service
class RestWrapColorServiceImpl implements RestWrapColorService {
    @Override
    public Mono<RestColor> restWrapColor() {
        return Mono.just(RestColor.BLUE);
    }
}

@Service
class RestWrapTextServiceImpl implements RestWrapTextService {
    @Override
    public Mono<String> restWrapText(String v) {
        return Mono.just("text:" + v);
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
    public Mono<RestNested> restNestedSpread(RestPerson person) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person)).build());
    }

    @Override
    public Mono<RestNested> restNestedSpreadOptional(RestPerson person) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person)).build());
    }

    @Override
    public Mono<RestNested> restNestedFlat(RestPerson person) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person)).build());
    }

    @Override
    public Mono<RestNested> restNestedLines(List<RestLine> lines) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.lines(lines)).build());
    }

    @Override
    public Mono<RestNested> restNestedJson(RestPerson person) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person)).build());
    }

    @Override
    public Mono<RestNested> restNestedForm(RestPerson person, List<RestLine> lines, String note) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person) + "/" + RestNestedSummaries.lines(lines) + "/" + (note == null ? "-" : note)).build());
    }

    @Override
    public Mono<RestNested> restNestedFormJson(RestPerson person) {
        return Mono.just(RestNested.builder().summary(RestNestedSummaries.person(person)).build());
    }
}
