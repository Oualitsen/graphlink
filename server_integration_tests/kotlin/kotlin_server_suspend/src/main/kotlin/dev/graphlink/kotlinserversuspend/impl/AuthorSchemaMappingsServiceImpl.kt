package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.interfaces.GlArticleProjection
import dev.graphlink.kotlinserversuspend.generated.services.AuthorSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.types.Article
import dev.graphlink.kotlinserversuspend.generated.types.Author
import graphql.GraphQLContext
import org.springframework.stereotype.Service

@Service
class AuthorSchemaMappingsServiceImpl : AuthorSchemaMappingsService {

    override suspend fun authorArticles(
        value: List<Author>,
        graphQLContext: GraphQLContext,
    ): Map<Author, List<GlArticleProjection>?> {
        val result = mutableMapOf<Author, List<GlArticleProjection>?>()
        for (author in value) {
            result[author] = Data.articles.filter { it.authorId == author.id }
        }
        return result
    }

    override suspend fun authorLatestArticles(limit: Int, value: Author): List<Article> =
        Data.articles.filter { it.authorId == value.id }.take(limit)
}
