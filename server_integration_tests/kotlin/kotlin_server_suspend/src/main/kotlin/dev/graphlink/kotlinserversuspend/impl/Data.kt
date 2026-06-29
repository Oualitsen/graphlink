package dev.graphlink.kotlinserversuspend.impl

import com.fasterxml.jackson.databind.ObjectMapper
import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

object Data {
    private val fixtures: Map<*, *> = ObjectMapper().readValue(
        File(System.getenv("FIXTURES_PATH") ?: "../../fixtures.json"), Map::class.java
    )

    @Suppress("UNCHECKED_CAST")
    val authors: MutableList<Author> = Collections.synchronizedList(
        (fixtures["authors"] as List<Map<String, Any?>>).map { Author.fromJson(it) }.toMutableList()
    )

    @Suppress("UNCHECKED_CAST")
    val articles: MutableList<Article> = Collections.synchronizedList(
        (fixtures["articles"] as List<Map<String, Any?>>).map { Article.fromJson(it) }.toMutableList()
    )

    private val nextArticleId = AtomicInteger(fixtures["nextId"] as Int)

    fun nextId(): String = nextArticleId.getAndIncrement().toString()
}
