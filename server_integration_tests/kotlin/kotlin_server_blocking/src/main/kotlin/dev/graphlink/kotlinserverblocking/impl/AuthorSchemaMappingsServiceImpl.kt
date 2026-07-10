package dev.graphlink.kotlinserverblocking.impl


import dev.graphlink.kotlinserverblocking.generated.services.AuthorSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import dev.graphlink.kotlinserverblocking.generated.types.Author
import org.springframework.stereotype.Service

@Service
class AuthorSchemaMappingsServiceImpl : AuthorSchemaMappingsService {

    override fun authorArticles(
        value: List<Author>
    ): Map<Author, List<Article>?> {
        val result = mutableMapOf<Author, List<Article>?>()
        for (author in value) {
            result[author] = Data.articles.filter { it.authorId == author.id }
        }
        return result
    }

    override fun authorLatestArticles(limit: Int, value: Author): List<Article> =
        Data.articles.filter { it.authorId == value.id }.take(limit)
}
