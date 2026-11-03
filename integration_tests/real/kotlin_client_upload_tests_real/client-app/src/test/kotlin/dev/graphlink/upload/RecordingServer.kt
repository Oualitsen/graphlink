package dev.graphlink.upload

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.security.MessageDigest
import java.util.concurrent.CopyOnWriteArrayList

fun sha256Of(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

class ReceivedPart(val name: String, val filename: String?, val contentType: String?, val bytes: ByteArray) {
    val sha256: String get() = sha256Of(bytes)
    val text: String get() = String(bytes, Charsets.UTF_8)
}

class Received(val contentLength: Long, val chunked: Boolean, val parts: List<ReceivedPart>) {
    fun part(name: String): ReceivedPart = parts.first { it.name == name }
}

/** GraphQL endpoint that records every multipart request as it arrived on the wire. */
class RecordingServer : AutoCloseable {
    val requests = CopyOnWriteArrayList<Received>()
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)

    init {
        server.createContext("/graphql") { exchange ->
            val body = exchange.requestBody.readAllBytes()
            val contentType = exchange.requestHeaders.getFirst("Content-Type")
            val length = exchange.requestHeaders.getFirst("Content-Length")
            val encoding = exchange.requestHeaders.getFirst("Transfer-Encoding")
            val boundary = Regex("boundary=([^;]+)").find(contentType ?: "")?.groupValues?.get(1)
            requests.add(
                Received(
                    length?.toLong() ?: -1,
                    encoding?.lowercase()?.contains("chunked") == true,
                    if (boundary == null) emptyList() else parse(body, boundary),
                ),
            )
            val response = """{"data":{"uploadOneFile":true,"uploadFileList":true}}""".toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, response.size.toLong())
            exchange.responseBody.write(response)
            exchange.close()
        }
        server.start()
    }

    val url: String get() = "http://127.0.0.1:${server.address.port}/graphql"

    fun only(): Received {
        check(requests.size == 1) { "expected one request, got ${requests.size}" }
        return requests[0]
    }

    override fun close() = server.stop(0)

    private fun parse(body: ByteArray, boundary: String): List<ReceivedPart> {
        val delimiter = "--$boundary".toByteArray()
        val headEnd = "\r\n\r\n".toByteArray()
        val starts = generateSequence(indexOf(body, delimiter, 0).takeIf { it >= 0 }) {
            indexOf(body, delimiter, it + delimiter.size).takeIf { next -> next >= 0 }
        }.toList()
        val disposition = Regex("name=\"([^\"]*)\"(?:; filename=\"([^\"]*)\")?")
        val type = Regex("(?i)content-type: ([^\\r\\n]+)")
        return (0 until starts.size - 1).map { i ->
            val from = starts[i] + delimiter.size + 2
            val to = starts[i + 1] - 2
            val headerEnd = indexOf(body, headEnd, from)
            val headers = String(body, from, headerEnd - from, Charsets.UTF_8)
            val d = disposition.find(headers)!!
            ReceivedPart(
                d.groupValues[1],
                d.groups[2]?.value,
                type.find(headers)?.groupValues?.get(1),
                body.copyOfRange(headerEnd + 4, to),
            )
        }
    }

    private fun indexOf(haystack: ByteArray, needle: ByteArray, start: Int): Int {
        outer@ for (i in start..haystack.size - needle.size) {
            for (j in needle.indices) if (haystack[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }
}
