package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.enums.ArticleType
import dev.graphlink.kotlinserverblocking.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserverblocking.generated.inputs.UpdateArticleInput
import dev.graphlink.kotlinserverblocking.generated.interfaces.Artcile
import dev.graphlink.kotlinserverblocking.generated.services.ArticleService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import graphql.GraphQLContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flowOf
import org.springframework.stereotype.Service

@Service
class ArticleServiceImpl : ArticleService {
    private val articleCreatedFlow = MutableSharedFlow<Article>(extraBufferCapacity = 16)
    private val articleUpdatedFlow = MutableSharedFlow<Article>(extraBufferCapacity = 16)

    override fun getArticle(id: String): Article = Data.articles.first { it.id == id }

    override fun listArticles(): List<Article> = Data.articles.toList()

    override fun createArticle(input: CreateArticleInput): Article {
        val article = Article(
            id = Data.nextId(),
            title = input.title,
            authorId = input.authorId,
            published = false,
        )
        Data.articles.add(article)
        articleCreatedFlow.tryEmit(article)
        return article
    }

    override fun updateArticle(input: UpdateArticleInput): Article {
        val article = Data.articles.first { it.id == input.id }
        val updated = input.title?.let { article.copy(title = it) } ?: article
        Data.articles[Data.articles.indexOf(article)] = updated
        articleUpdatedFlow.tryEmit(updated)
        return updated
    }

    override fun articleCreated(): Flow<Article> = articleCreatedFlow.asSharedFlow()

    override fun articleUpdated(id: String): Flow<Article> =
        articleUpdatedFlow.asSharedFlow().filter { it.id == id }

    override fun articleDeleted(): Flow<String> = flowOf("deleted-1", "deleted-2")

    // Article implements Artcile, so a concrete article is a valid
    // projection — the client selects whichever subset it wants.
    override fun getProjectedArticle(graphQLContext: GraphQLContext): Artcile =
        Data.articles.first()

    override fun getArticleInfo(graphQLContext: GraphQLContext): Artcile? =
        Data.articles.firstOrNull()

    override fun getArticleWithCount(): Article? = Data.articles.firstOrNull()

    override fun getArticleTypes(): List<ArticleType> =
        listOf(ArticleType.NEWS, ArticleType.BLOG, ArticleType.REVIEW)
}
