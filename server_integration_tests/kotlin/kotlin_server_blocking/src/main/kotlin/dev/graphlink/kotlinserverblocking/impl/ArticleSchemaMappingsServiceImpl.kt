package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.ArticleSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.ArticleWithCountSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import dev.graphlink.kotlinserverblocking.generated.types.Author
import org.springframework.stereotype.Service

@Service
class ArticleSchemaMappingsServiceImpl :
    ArticleSchemaMappingsService, ArticleWithCountSchemaMappingsService {

    override fun articleAuthor(value: Article): Author =
        Data.authors.first { it.id == value.authorId }

    override fun articleAuthorList(value: Article): List<Author>? =
        Data.authors.filter { it.id == value.authorId }

    override fun articleWithCountCount(value: Article): Int = Data.articles.indexOf(value) + 1
}
