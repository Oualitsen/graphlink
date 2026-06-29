package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.AuthorSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import org.springframework.stereotype.Service

@Service
class AuthorSchemaMappingsServiceImpl : AuthorSchemaMappingsService {
    override suspend fun authorArticles(value: List<Author>): Map<Author, List<Article>> =
        value.associateWith { author -> Data.articles.filter { it.authorId == author.id } }

    override suspend fun authorLatestArticles(value: Author, limit: Int): List<Article> =
        Data.articles.filter { it.authorId == value.id }.take(limit)
}
