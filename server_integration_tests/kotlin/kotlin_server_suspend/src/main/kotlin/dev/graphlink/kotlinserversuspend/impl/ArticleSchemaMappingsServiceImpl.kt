package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.ArticleSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.ArticleWithCountSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import org.springframework.stereotype.Service

@Service
class ArticleSchemaMappingsServiceImpl :
    ArticleSchemaMappingsService, ArticleWithCountSchemaMappingsService {

    override suspend fun articleAuthor(value: Article): Author =
        Data.authors.first { it.id == value.authorId }

    override suspend fun articleAuthorList(value: Article): List<Author>? =
        Data.authors.filter { it.id == value.authorId }

    override suspend fun articleWithCountCount(value: Article): Int = Data.articles.indexOf(value) + 1
}
