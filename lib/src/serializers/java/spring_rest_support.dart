const springRestSupportFileName = 'GraphLinkRest.java';

/// Emitted once per Spring server that has REST operations. `decode` turns a malformed request value into a 400, `json`
/// makes a plain String travel as a JSON string (a bare String return would be written as text by Spring).
///
/// Package-agnostic: `writeToFile` prepends `package <base>.<subdir>;`.
const springRestSupportSource = '''
import graphql.GraphQLContext;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

import org.springframework.http.HttpStatus;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.http.codec.multipart.Part;
import org.springframework.util.MultiValueMap;
import org.springframework.web.server.ResponseStatusException;

import com.fasterxml.jackson.annotation.JsonValue;

public final class GraphLinkRest {

   private GraphLinkRest() {}

   public static <T> T decode(Supplier<T> conversion) {
      try {
         return conversion.get();
      } catch (RuntimeException e) {
         throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid request value");
      }
   }

   public static FilePart filePart(Part part) {
      if (part == null) return null;
      if (part instanceof FilePart file) return file;
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Expected a file");
   }

   public static GraphQLContext context(Object request) {
      return GraphQLContext.newContext().of("request", request).build();
   }

   public static String field(MultiValueMap<String, String> form, String name, boolean required) {
      String value = form == null ? null : form.getFirst(name);
      if (value == null && required) {
         throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Missing form field " + name);
      }
      return value;
   }

   public static String field(MultiValueMap<String, String> form, String name, String defaultValue) {
      String value = form == null ? null : form.getFirst(name);
      return value == null ? defaultValue : value;
   }

   public static List<String> fields(MultiValueMap<String, String> form, String name, boolean required) {
      List<String> values = form == null ? null : form.get(name);
      if (values == null || values.isEmpty()) {
         if (required) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Missing form field " + name);
         }
         return null;
      }
      return values.stream().flatMap(value -> Arrays.stream(value.split(","))).toList();
   }

   public static boolean bool(String value) {
      if ("true".equals(value)) return true;
      if ("false".equals(value)) return false;
      throw new IllegalArgumentException("Invalid boolean");
   }

   public static Object wrap(Object value, String... path) {
      Object result = value;
      for (int i = path.length - 1; i >= 0; i--) {
         Map<String, Object> level = new LinkedHashMap<>();
         level.put(path[i], result);
         result = level;
      }
      return result;
   }

   public static Object json(String value) {
      return value == null ? null : new JsonString(value);
   }

   public static final class JsonString {
      private final String value;

      private JsonString(String value) {
         this.value = value;
      }

      @JsonValue
      public String getValue() {
         return value;
      }
   }
}
''';

const springRestUploadFileName = 'GraphLinkRestUpload.java';

/// Emitted when a REST operation takes a raw upload body (servlet stack only: it reads the `HttpServletRequest`).
const springRestUploadSource = '''
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

import org.springframework.web.multipart.MultipartFile;

import jakarta.servlet.http.HttpServletRequest;

public final class GraphLinkRestUpload {

   private GraphLinkRestUpload() {}

   public static MultipartFile rawFile(HttpServletRequest request) {
      return new RawFile(request);
   }

   private static final class RawFile implements MultipartFile {
      private final HttpServletRequest request;

      private RawFile(HttpServletRequest request) {
         this.request = request;
      }

      @Override
      public String getName() {
         return "file";
      }

      @Override
      public String getOriginalFilename() {
         return "";
      }

      @Override
      public String getContentType() {
         return request.getContentType();
      }

      @Override
      public boolean isEmpty() {
         return request.getContentLengthLong() == 0;
      }

      @Override
      public long getSize() {
         return request.getContentLengthLong();
      }

      @Override
      public byte[] getBytes() throws IOException {
         return request.getInputStream().readAllBytes();
      }

      @Override
      public InputStream getInputStream() throws IOException {
         return request.getInputStream();
      }

      @Override
      public void transferTo(File dest) throws IOException {
         Files.copy(request.getInputStream(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING);
      }
   }
}
''';

const springRestReactiveUploadSource = '''
import java.nio.file.Path;

import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.core.io.buffer.DataBufferUtils;
import org.springframework.http.HttpHeaders;
import org.springframework.http.codec.multipart.FilePart;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public final class GraphLinkRestUpload {

   private GraphLinkRestUpload() {}

   public static FilePart rawFile(HttpHeaders headers, Flux<DataBuffer> body) {
      return new RawFile(headers, body == null ? Flux.empty() : body);
   }

   private static final class RawFile implements FilePart {
      private final HttpHeaders headers;
      private final Flux<DataBuffer> body;

      private RawFile(HttpHeaders headers, Flux<DataBuffer> body) {
         this.headers = headers;
         this.body = body;
      }

      @Override
      public String name() {
         return "file";
      }

      @Override
      public String filename() {
         return "";
      }

      @Override
      public HttpHeaders headers() {
         return headers;
      }

      @Override
      public Flux<DataBuffer> content() {
         return body;
      }

      @Override
      public Mono<Void> transferTo(Path dest) {
         return DataBufferUtils.write(body, dest);
      }

      @Override
      public Mono<Void> delete() {
         return Mono.empty();
      }
   }
}
''';

const springRestDownloadFileName = 'GraphLinkDownload.java';

/// What a service returns for a `@glDownload` scalar: the bytes (any Spring `Resource`, streamed as is) and, optionally,
/// the file name offered to the client and the content type (guessed from the resource when absent).
const springRestDownloadSource = '''
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.MediaTypeFactory;
import org.springframework.http.ResponseEntity;

public final class GraphLinkDownload {

   private final Resource resource;
   private final String filename;
   private final String contentType;

   public GraphLinkDownload(Resource resource, String filename, String contentType) {
      this.resource = resource;
      this.filename = filename;
      this.contentType = contentType;
   }

   public static GraphLinkDownload of(Resource resource) {
      return new GraphLinkDownload(resource, null, null);
   }

   public Resource getResource() {
      return resource;
   }

   public String getFilename() {
      return filename;
   }

   public String getContentType() {
      return contentType;
   }

   public static ResponseEntity<Resource> toResponse(GraphLinkDownload download) {
      if (download == null) {
         return ResponseEntity.noContent().build();
      }
      ResponseEntity.BodyBuilder builder = ResponseEntity.ok();
      builder.contentType(mediaTypeOf(download));
      if (download.filename != null) {
         Charset charset = download.filename.chars().allMatch(c -> c >= 0x20 && c < 0x7f) ? null : StandardCharsets.UTF_8;
         builder.header(HttpHeaders.CONTENT_DISPOSITION,
               ContentDisposition.attachment().filename(download.filename, charset).build().toString());
      }
      return builder.body(download.resource);
   }

   private static MediaType mediaTypeOf(GraphLinkDownload download) {
      if (download.contentType != null) {
         return MediaType.parseMediaType(download.contentType);
      }
      return MediaTypeFactory.getMediaType(download.filename != null ? download.filename : download.resource.getFilename())
            .orElse(MediaType.APPLICATION_OCTET_STREAM);
   }
}
''';

const springRestParamsFileName = 'GraphLinkRestParams.java';

/// Reads an input object, a list of them or a JSON text out of the request parameters (query string or form): keys
/// nest with dots (`address.city`, `items.0.name`) or brackets (`address[city]`, `items[0][name]`), as the clients write them.
const springRestParamsSource = '''
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

import org.springframework.http.HttpStatus;
import org.springframework.util.MultiValueMap;
import org.springframework.web.server.ResponseStatusException;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

public final class GraphLinkRestParams {

   private static final ObjectMapper MAPPER = new ObjectMapper();
   private static final Pattern INTEGER = Pattern.compile("-?\\\\d+");
   private static final Pattern DECIMAL = Pattern.compile("-?\\\\d+(\\\\.\\\\d+)?([eE][+-]?\\\\d+)?");

   private GraphLinkRestParams() {}

   public static final class Shape {
      private enum Kind { STRING, INT, FLOAT, BOOLEAN, ENUM, OBJECT, LIST }

      public static final Shape STRING = new Shape(Kind.STRING);
      public static final Shape INT = new Shape(Kind.INT);
      public static final Shape FLOAT = new Shape(Kind.FLOAT);
      public static final Shape BOOLEAN = new Shape(Kind.BOOLEAN);

      private final Kind kind;
      private List<String> values = List.of();
      private Shape element;
      private final List<Field> fields = new ArrayList<>();

      private Shape(Kind kind) {
         this.kind = kind;
      }

      public static Shape enumOf(String... values) {
         Shape shape = new Shape(Kind.ENUM);
         shape.values = Arrays.asList(values);
         return shape;
      }

      public static Shape list(Shape element) {
         Shape shape = new Shape(Kind.LIST);
         shape.element = element;
         return shape;
      }

      public static Shape obj() {
         return new Shape(Kind.OBJECT);
      }

      public Shape field(String name, String wireName, Shape shape) {
         fields.add(new Field(name, wireName, shape));
         return this;
      }
   }

   private static final class Field {
      private final String name;
      private final String wireName;
      private final Shape shape;

      private Field(String name, String wireName, Shape shape) {
         this.name = name;
         this.wireName = wireName;
         this.shape = shape;
      }
   }

   @SuppressWarnings("unchecked")
   public static <T> T nested(MultiValueMap<String, String> params, String prefix, Shape shape, boolean required) {
      Object value = read(params, List.of(prefix), shape);
      if (value == null && required) {
         if (shape.kind != Shape.Kind.OBJECT) {
            throw new IllegalArgumentException("Missing value");
         }
         value = new LinkedHashMap<String, Object>();
      }
      return (T) value;
   }

   @SuppressWarnings("unchecked")
   public static <T> T json(MultiValueMap<String, String> params, String name, boolean required) {
      String text = params.getFirst(name);
      if (text == null) {
         if (required) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Missing " + name);
         }
         return null;
      }
      try {
         return (T) MAPPER.readValue(text, Object.class);
      } catch (JsonProcessingException e) {
         throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid JSON in " + name);
      }
   }

   private static List<String> children(List<String> keys, String name) {
      List<String> result = new ArrayList<>();
      for (String key : keys) {
         if (key.isEmpty()) {
            result.add(name);
         } else {
            result.add(key + "." + name);
            result.add(key + "[" + name + "]");
         }
      }
      return result;
   }

   private static List<String> values(MultiValueMap<String, String> params, List<String> keys) {
      List<String> result = new ArrayList<>();
      for (String key : keys) {
         List<String> found = params.get(key);
         if (found != null) {
            result.addAll(found);
         }
      }
      return result;
   }

   private static Object read(MultiValueMap<String, String> params, List<String> keys, Shape shape) {
      switch (shape.kind) {
         case OBJECT: {
            Map<String, Object> result = new LinkedHashMap<>();
            for (Field field : shape.fields) {
               Object child = read(params, children(keys, field.wireName), field.shape);
               if (child != null) {
                  result.put(field.name, child);
               }
            }
            return result.isEmpty() ? null : result;
         }
         case LIST: {
            if (shape.element.kind != Shape.Kind.OBJECT && shape.element.kind != Shape.Kind.LIST) {
               List<Object> items = new ArrayList<>();
               for (String value : values(params, keys)) {
                  for (String part : value.split(",")) {
                     items.add(scalar(part, shape.element));
                  }
               }
               return items.isEmpty() ? null : items;
            }
            List<Object> items = new ArrayList<>();
            for (int index = 0; ; index++) {
               Object item = read(params, children(keys, String.valueOf(index)), shape.element);
               if (item == null) {
                  break;
               }
               items.add(item);
            }
            return items.isEmpty() ? null : items;
         }
         default: {
            List<String> found = values(params, keys);
            return found.isEmpty() ? null : scalar(found.get(0), shape);
         }
      }
   }

   private static Object scalar(String text, Shape shape) {
      switch (shape.kind) {
         case INT:
            if (!INTEGER.matcher(text).matches()) {
               throw new IllegalArgumentException("Invalid integer");
            }
            return Integer.valueOf(text);
         case FLOAT:
            if (!DECIMAL.matcher(text).matches()) {
               throw new IllegalArgumentException("Invalid number");
            }
            return Double.valueOf(text);
         case BOOLEAN:
            if ("true".equals(text)) {
               return Boolean.TRUE;
            }
            if ("false".equals(text)) {
               return Boolean.FALSE;
            }
            throw new IllegalArgumentException("Invalid boolean");
         case ENUM:
            if (!shape.values.contains(text)) {
               throw new IllegalArgumentException("Invalid enum value");
            }
            return text;
         default:
            return text;
      }
   }
}
''';
