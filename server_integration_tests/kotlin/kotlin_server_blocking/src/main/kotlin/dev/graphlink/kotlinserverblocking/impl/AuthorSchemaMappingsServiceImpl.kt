package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.interfaces.Artcile
import dev.graphlink.kotlinserverblocking.generated.services.AuthorSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import dev.graphlink.kotlinserverblocking.generated.types.Author
import graphql.GraphQLContext
import org.springframework.stereotype.Service

@Service
class AuthorSchemaMappingsServiceImpl : AuthorSchemaMappingsService {

    override fun authorArticles(
        value: List<Author>,
        graphQLContext: GraphQLContext,
    ): Map<Author, List<Artcile>?> {
        val result = mutableMapOf<Author, List<Artcile>?>()
        for (author in value) {
            result[author] = Data.articles.filter { it.authorId == author.id }
        }
        return result
    }

    override fun authorLatestArticles(limit: Int, value: Author): List<Article> =
        Data.articles.filter { it.authorId == value.id }.take(limit)
}
