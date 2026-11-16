const kotlinRestSupportFileName = 'GraphLinkRest.kt';

/// Kotlin counterpart of `spring_rest_support.dart`.
///
/// Package-agnostic: `writeToFile` prepends `package <base>.<subdir>`.
const kotlinRestSupportSource = '''
import com.fasterxml.jackson.annotation.JsonValue
import graphql.GraphQLContext
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException

object GraphLinkRest {

    fun <T> decode(conversion: () -> T): T =
        try {
            conversion()
        } catch (e: RuntimeException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid request value")
        }

    fun context(request: Any): GraphQLContext = GraphQLContext.newContext().of("request", request).build()

    fun wrap(value: Any?, vararg path: String): Any? = path.foldRight(value) { key, inner -> mapOf(key to inner) }

    fun json(value: String?): Any? = value?.let { JsonString(it) }

    class JsonString(@get:JsonValue val value: String)
}
''';

const kotlinRestUploadFileName = 'GraphLinkRestUpload.kt';

const kotlinRestUploadSource = '''
import jakarta.servlet.http.HttpServletRequest
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import org.springframework.web.multipart.MultipartFile

object GraphLinkRestUpload {

    fun rawFile(request: HttpServletRequest): MultipartFile = RawFile(request)

    private class RawFile(private val request: HttpServletRequest) : MultipartFile {
        override fun getName(): String = "file"

        override fun getOriginalFilename(): String = ""

        override fun getContentType(): String? = request.contentType

        override fun isEmpty(): Boolean = request.contentLengthLong == 0L

        override fun getSize(): Long = request.contentLengthLong

        override fun getBytes(): ByteArray = request.inputStream.readAllBytes()

        override fun getInputStream(): InputStream = request.inputStream

        override fun transferTo(dest: File) {
            Files.copy(request.inputStream, dest.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }
}
''';

const kotlinRestDownloadFileName = 'GraphLinkDownload.kt';

const kotlinRestDownloadSource = '''
import java.nio.charset.StandardCharsets
import org.springframework.core.io.Resource
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.MediaTypeFactory
import org.springframework.http.ResponseEntity

class GraphLinkDownload(val resource: Resource, val filename: String? = null, val contentType: String? = null) {

    companion object {
        @JvmStatic
        fun toResponse(download: GraphLinkDownload?): ResponseEntity<Resource> {
            if (download == null) return ResponseEntity.noContent().build()
            val builder = ResponseEntity.ok()
            builder.contentType(mediaTypeOf(download))
            download.filename?.let { name ->
                val charset = if (name.all { it.code in 0x20..0x7e }) null else StandardCharsets.UTF_8
                builder.header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment().filename(name, charset).build().toString())
            }
            return builder.body(download.resource)
        }

        private fun mediaTypeOf(download: GraphLinkDownload): MediaType {
            download.contentType?.let { return MediaType.parseMediaType(it) }
            return MediaTypeFactory.getMediaType(download.filename ?: download.resource.filename)
                .orElse(MediaType.APPLICATION_OCTET_STREAM)
        }
    }
}
''';

const kotlinRestParamsFileName = 'GraphLinkRestParams.kt';

const kotlinRestParamsSource = '''
import com.fasterxml.jackson.core.JsonProcessingException
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.http.HttpStatus
import org.springframework.util.MultiValueMap
import org.springframework.web.server.ResponseStatusException

object GraphLinkRestParams {

    private val mapper = ObjectMapper()
    private val integer = Regex("-?\\\\d+")
    private val decimal = Regex("-?\\\\d+(\\\\.\\\\d+)?([eE][+-]?\\\\d+)?")

    class Shape private constructor(private val kind: Kind) {
        internal enum class Kind { STRING, INT, FLOAT, BOOLEAN, ENUM, OBJECT, LIST }

        internal class Field(val name: String, val wireName: String, val shape: Shape)

        internal var values: List<String> = emptyList()
        internal var element: Shape? = null
        internal val fields = mutableListOf<Field>()
        internal fun kind() = kind

        fun field(name: String, wireName: String, shape: Shape): Shape {
            fields.add(Field(name, wireName, shape))
            return this
        }

        companion object {
            val STRING = Shape(Kind.STRING)
            val INT = Shape(Kind.INT)
            val FLOAT = Shape(Kind.FLOAT)
            val BOOLEAN = Shape(Kind.BOOLEAN)

            fun enumOf(vararg values: String): Shape = Shape(Kind.ENUM).also { it.values = values.toList() }

            fun list(element: Shape): Shape = Shape(Kind.LIST).also { it.element = element }

            fun obj(): Shape = Shape(Kind.OBJECT)
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun <T> nested(params: MultiValueMap<String, String>, prefix: String, shape: Shape, required: Boolean): T {
        var value = read(params, listOf(prefix), shape)
        if (value == null && required) {
            if (shape.kind() != Shape.Kind.OBJECT) throw IllegalArgumentException("Missing value")
            value = LinkedHashMap<String, Any?>()
        }
        return value as T
    }

    @Suppress("UNCHECKED_CAST")
    fun <T> json(params: MultiValueMap<String, String>, name: String, required: Boolean): T {
        val text = params.getFirst(name)
        if (text == null) {
            if (required) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Missing \$name")
            return null as T
        }
        try {
            return mapper.readValue(text, Any::class.java) as T
        } catch (e: JsonProcessingException) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid JSON in \$name")
        }
    }

    private fun children(keys: List<String>, name: String): List<String> =
        keys.flatMap { key -> if (key.isEmpty()) listOf(name) else listOf("\$key.\$name", "\$key[\$name]") }

    private fun values(params: MultiValueMap<String, String>, keys: List<String>): List<String> =
        keys.flatMap { params[it] ?: emptyList() }

    private fun read(params: MultiValueMap<String, String>, keys: List<String>, shape: Shape): Any? =
        when (shape.kind()) {
            Shape.Kind.OBJECT -> {
                val result = LinkedHashMap<String, Any?>()
                for (field in shape.fields) {
                    read(params, children(keys, field.wireName), field.shape)?.let { result[field.name] = it }
                }
                result.ifEmpty { null }
            }
            Shape.Kind.LIST -> {
                val element = shape.element!!
                val items = mutableListOf<Any?>()
                if (element.kind() != Shape.Kind.OBJECT && element.kind() != Shape.Kind.LIST) {
                    values(params, keys).forEach { value -> value.split(",").forEach { items.add(scalar(it, element)) } }
                } else {
                    var index = 0
                    while (true) {
                        val item = read(params, children(keys, index.toString()), element) ?: break
                        items.add(item)
                        index++
                    }
                }
                items.ifEmpty { null }
            }
            else -> values(params, keys).firstOrNull()?.let { scalar(it, shape) }
        }

    private fun scalar(text: String, shape: Shape): Any =
        when (shape.kind()) {
            Shape.Kind.INT -> if (integer.matches(text)) text.toInt() else throw IllegalArgumentException("Invalid integer")
            Shape.Kind.FLOAT -> if (decimal.matches(text)) text.toDouble() else throw IllegalArgumentException("Invalid number")
            Shape.Kind.BOOLEAN -> when (text) {
                "true" -> true
                "false" -> false
                else -> throw IllegalArgumentException("Invalid boolean")
            }
            Shape.Kind.ENUM -> if (text in shape.values) text else throw IllegalArgumentException("Invalid enum value")
            else -> text
        }
}
''';
