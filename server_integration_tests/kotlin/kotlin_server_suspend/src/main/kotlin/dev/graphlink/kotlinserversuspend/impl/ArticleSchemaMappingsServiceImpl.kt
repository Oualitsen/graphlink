package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.ArticleSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import org.springframework.stereotype.Service

@Service
class ArticleSchemaMappingsServiceImpl : ArticleSchemaMappingsService {
    override suspend fun articleAuthor(value: Article): Author =
        Data.authors.find { it.id == value.authorId }
            ?: throw NoSuchElementException("Author not found: ${value.authorId}")
}
