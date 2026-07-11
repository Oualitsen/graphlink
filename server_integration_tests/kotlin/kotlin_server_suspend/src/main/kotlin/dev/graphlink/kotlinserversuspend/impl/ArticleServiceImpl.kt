package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.enums.ArticleType
import dev.graphlink.kotlinserversuspend.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserversuspend.generated.inputs.UpdateArticleInput
import dev.graphlink.kotlinserversuspend.generated.services.ArticleService
import dev.graphlink.kotlinserversuspend.generated.types.Article
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

    override suspend fun getArticle(id: String): Article = Data.articles.first { it.id == id }

    override suspend fun listArticles(): List<Article> = Data.articles.toList()

    override suspend fun createArticle(input: CreateArticleInput): Article {
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

    override suspend fun updateArticle(input: UpdateArticleInput): Article {
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

    // Article implements Article, so a concrete article is a valid
    // projection — the client selects whichever subset it wants.
    override suspend fun getProjectedArticle(): Article =
        Data.articles.first()

    override suspend fun getArticleInfo(): Article? =
        Data.articles.firstOrNull()

    override suspend fun getArticleWithCount(): Article? = Data.articles.firstOrNull()

    override suspend fun getArticleTypes(): List<ArticleType> =
        listOf(ArticleType.NEWS, ArticleType.BLOG, ArticleType.REVIEW)
}
