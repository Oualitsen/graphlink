package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.rest.GraphLinkDownload
import dev.graphlink.kotlinserversuspend.generated.enums.RestColor
import dev.graphlink.kotlinserversuspend.generated.inputs.RestFilter
import dev.graphlink.kotlinserversuspend.generated.inputs.RestLine
import dev.graphlink.kotlinserversuspend.generated.inputs.RestPerson
import dev.graphlink.kotlinserversuspend.generated.inputs.RestItemInput
import dev.graphlink.kotlinserversuspend.generated.inputs.RestMeta
import dev.graphlink.kotlinserversuspend.generated.services.*
import dev.graphlink.kotlinserversuspend.generated.types.*
import graphql.GraphQLContext
import org.springframework.core.io.ByteArrayResource
import org.springframework.core.io.InputStreamResource
import org.springframework.stereotype.Service
import java.io.InputStream
import org.springframework.web.multipart.MultipartFile

private fun item(id: String, name: String, qty: Int, color: RestColor?, tags: List<String>?) =
    RestItem(id = id, name = name, qty = qty, color = color, tags = tags ?: emptyList())

private fun fromInput(id: String, input: RestItemInput) = item(id, input.name, input.qty, input.color, input.tags)

@Service
class RestItemServiceImpl : RestItemService {
    override suspend fun restItem(id: String): RestItem? = if (id == "missing") null else item(id, "item-$id", 1, null, null)

    override suspend fun restItemByColor(color: RestColor): RestItem =
        item(color.toJson().lowercase(), "color-${color.toJson()}", 1, color, listOf(color.toJson().lowercase()))

    override suspend fun restItemGraphql(id: String): RestItem? = restItem(id)

    override suspend fun restCreate(input: RestItemInput): RestItem = fromInput("new-${input.name}", input)

    override suspend fun restReplace(id: String, input: RestItemInput): RestItem = fromInput(id, input)

    override suspend fun restPatch(id: String, name: String?): RestItem = item(id, name ?: "item-$id", 1, null, null)

    override suspend fun restBulk(items: List<RestItemInput>): List<RestItem> = items.mapIndexed { i, input -> fromInput("bulk-$i", input) }
}

@Service
class RestScalarsServiceImpl : RestScalarsService {
    override suspend fun restScalars(n: Int, ratio: Double, flag: Boolean, text: String) = RestScalars(n = n, ratio = ratio, flag = flag, text = text)

    override suspend fun restFail(code: Int): RestScalars = throw IllegalStateException("boom $code")
}

@Service
class RestSearchServiceImpl : RestSearchService {
    override suspend fun restSearch(filter: RestFilter?, limit: Int?, offset: Int?, order: RestColor?) = RestSearch(
        tag = filter?.tag,
        minQty = filter?.minQty,
        maxPrice = filter?.maxPrice,
        colors = filter?.colors,
        inStock = filter?.inStock,
        limit = limit ?: 10,
        offset = offset,
        order = order,
    )
}

@Service
class RestTagsServiceImpl : RestTagsService {
    override suspend fun restTags(tags: List<String>, ids: List<Int>?): List<String> = tags + (ids ?: emptyList()).map { "#$it" }
}

@Service
class RestGreetingServiceImpl : RestGreetingService {
    override suspend fun restGreeting(name: String) = "hello $name"
}

@Service
class RestPlainServiceImpl : RestPlainService {
    override suspend fun restPlain(name: String) = "plain $name"
}

@Service
class RestCountServiceImpl : RestCountService {
    override suspend fun restCount() = 42
}

@Service
class RestFlagServiceImpl : RestFlagService {
    override suspend fun restFlag(on: Boolean) = !on
}

@Service
class RestColorsServiceImpl : RestColorsService {
    override suspend fun restColors() = listOf(RestColor.RED, RestColor.GREEN, RestColor.BLUE)
}

@Service
class RestHeadersServiceImpl : RestHeadersService {
    override suspend fun restHeaders(token: String, trace: String?, meta: RestMeta?) =
        RestHeaders(token = token, trace = trace, traceId = meta?.traceId, version = meta?.version)
}

@Service
class RestDeleteServiceImpl : RestDeleteService {
    override suspend fun restDelete(id: String): Void? = null
}

@Service
class RestOptionalBodyServiceImpl : RestOptionalBodyService {
    override suspend fun restOptionalBody(input: RestItemInput?) = input?.qty ?: -1
}

@Service
class RestValidatedServiceImpl : RestValidatedService {
    override suspend fun restValidated(name: String) = true

    override suspend fun validateRestValidated(name: String) {
        require(name != "invalid") { "invalid name" }
    }
}

@Service
class RestKeywordsServiceImpl : RestKeywordsService {
    override suspend fun restKeywords(switch: String, class_: String, return_: String?, if_: Int) =
        RestKeywords(class_ = class_, return_ = return_, if_ = if_, switch = switch)
}

private fun uploadInfo(file: MultipartFile, label: String?, kind: RestColor?, times: Int?): RestUploadInfo {
    val digest = java.security.MessageDigest.getInstance("SHA-256")
    var size = 0
    file.inputStream.use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            digest.update(buffer, 0, read)
            size += read
        }
    }
    return RestUploadInfo(
        filename = file.originalFilename?.takeIf { it.isNotEmpty() },
        contentType = file.contentType,
        size = size,
        sha256 = java.util.HexFormat.of().formatHex(digest.digest()),
        label = label,
        kind = kind,
        times = times,
    )
}

@Service
class RestUploadInfoServiceImpl : RestUploadInfoService {
    override suspend fun restUpload(label: String?, kind: RestColor?, times: Int?, file: MultipartFile) = uploadInfo(file, label, kind, times)

    override suspend fun restUploadMany(label: String?, files: List<MultipartFile>) = files.map { uploadInfo(it, label, null, null) }

    override suspend fun restUploadRaw(id: String, name: String?, file: MultipartFile) = uploadInfo(file, name, null, null)
}

@Service
class RestUploadOptionalServiceImpl : RestUploadOptionalService {
    override suspend fun restUploadOptional(file: MultipartFile?) = file?.size?.toInt() ?: -1
}

@Service
class RestFormEchoServiceImpl : RestFormEchoService {
    override suspend fun restForm(name: String, qty: Int, color: RestColor?, flag: Boolean?, tags: List<String>?, note: String?) =
        RestFormEcho(id = null, name = name, qty = qty, color = color, flag = flag ?: false, tags = tags ?: emptyList(), note = note)

    override suspend fun restFormUpdate(id: String, name: String, qty: Int?) =
        RestFormEcho(id = id, name = name, qty = qty ?: 1, color = null, flag = false, tags = emptyList(), note = null)
}

@Service
class RestFormOptionalServiceImpl : RestFormOptionalService {
    override suspend fun restFormOptional(note: String?) = note?.length ?: -1
}

@Service
class RestMarkedServiceImpl : RestMarkedService {
    private fun marked(name: String, context: GraphQLContext?) =
        RestMarked(name = name, marker = context?.get<String?>("marker"), hasContext = context != null)

    override suspend fun restIntercepted(name: String, graphQLContext: GraphQLContext) = marked(name, graphQLContext)

    override suspend fun restInjected(name: String, graphQLContext: GraphQLContext) = marked(name, graphQLContext)

    override suspend fun restUnguarded(name: String) = marked(name, null)

    override suspend fun restBlockGuarded(name: String, graphQLContext: GraphQLContext) = marked(name, graphQLContext)

    override suspend fun restInterceptedBody(input: RestItemInput, graphQLContext: GraphQLContext) = marked(input.name, graphQLContext)
}

@Service
class RestInterceptedVoidServiceImpl : RestInterceptedVoidService {
    override suspend fun restInterceptedVoid(name: String, graphQLContext: GraphQLContext): Void? = null
}

private fun pattern(size: Int) = ByteArray(size) { (it % 251).toByte() }

private fun download(name: String, kind: String?) = when (kind) {
    "bin" -> GraphLinkDownload(ByteArrayResource(pattern(1000)), "data.bin")
    "nofile" -> GraphLinkDownload(ByteArrayResource("x".toByteArray()))
    "type" -> GraphLinkDownload(ByteArrayResource("{\"a\":1}".toByteArray()), contentType = "application/json")
    else -> GraphLinkDownload(ByteArrayResource("hello $name".toByteArray()), "$name.txt", "text/plain")
}

@Service
class RestDownloadServiceImpl : RestDownloadService {
    override suspend fun restDownload(name: String, kind: String?) = download(name, kind)
}

@Service
class RestDownloadOptionalServiceImpl : RestDownloadOptionalService {
    override suspend fun restDownloadOptional(name: String?): GraphLinkDownload? = name?.let { download(it, null) }
}

@Service
class RestDownloadLargeServiceImpl : RestDownloadLargeService {
    override suspend fun restDownloadLarge(size: Int): GraphLinkDownload {
        val stream = object : InputStream() {
            private var position = 0L

            override fun read(): Int = if (position < size) (position++ % 251).toInt() else -1

            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (position >= size) return -1
                val count = minOf(length.toLong(), size - position).toInt()
                for (i in 0 until count) buffer[offset + i] = ((position + i) % 251).toByte()
                position += count
                return count
            }
        }
        return GraphLinkDownload(InputStreamResource(stream), "large.bin")
    }
}

@Service
class RestWrapServiceImpl : RestWrapService {
    override suspend fun restWrapDeep(v: String) = RestWrap(value = v)

    override suspend fun restWrapList(n: Int) = List(n) { RestWrap(value = "item-$it") }

    override suspend fun restWrapNullable(on: Boolean): RestWrap? = if (on) RestWrap(value = "on") else null
}

@Service
class RestWrapColorServiceImpl : RestWrapColorService {
    override suspend fun restWrapColor() = RestColor.BLUE
}

@Service
class RestWrapTextServiceImpl : RestWrapTextService {
    override suspend fun restWrapText(v: String) = "text:$v"
}

private fun summary(person: RestPerson?): String =
    if (person == null) "none" else listOf(
        person.name,
        person.age?.toString() ?: "-",
        person.address?.city ?: "-",
        person.address?.zip?.toString() ?: "-",
        person.tags?.joinToString(",") ?: "-",
        person.kind?.toJson() ?: "-",
    ).joinToString("|")

private fun summary(lines: List<RestLine>?): String = lines?.joinToString(";") { "${it.sku}:${it.qty}" } ?: "-"

@Service
class RestNestedServiceImpl : RestNestedService {
    override suspend fun restNestedSpread(person: RestPerson) = RestNested(summary = summary(person))

    override suspend fun restNestedSpreadOptional(person: RestPerson?) = RestNested(summary = summary(person))

    override suspend fun restNestedFlat(person: RestPerson) = RestNested(summary = summary(person))

    override suspend fun restNestedLines(lines: List<RestLine>) = RestNested(summary = summary(lines))

    override suspend fun restNestedJson(person: RestPerson?) = RestNested(summary = summary(person))

    override suspend fun restNestedForm(person: RestPerson, lines: List<RestLine>?, note: String?) =
        RestNested(summary = summary(person) + "/" + summary(lines) + "/" + (note ?: "-"))

    override suspend fun restNestedFormJson(person: RestPerson) = RestNested(summary = summary(person))
}
