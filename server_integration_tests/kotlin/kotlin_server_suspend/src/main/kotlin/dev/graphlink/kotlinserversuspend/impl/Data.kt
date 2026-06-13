package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

object Data {
    val authors: MutableList<Author> = Collections.synchronizedList(
        mutableListOf(
            Author(id = "1", name = "Ramdane"),
            Author(id = "2", name = "Alice"),
        )
    )

    val articles: MutableList<Article> = Collections.synchronizedList(
        mutableListOf(
            Article(id = "1", title = "GraphLink Basics", authorId = "1"),
            Article(id = "2", title = "Advanced GraphLink", authorId = "1"),
            Article(id = "3", title = "Alice's First Post", authorId = "2"),
        )
    )

    private val nextArticleId = AtomicInteger(4)

    fun nextId(): String = nextArticleId.getAndIncrement().toString()
}
