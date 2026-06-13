package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserverblocking.generated.inputs.UpdateArticleInput
import dev.graphlink.kotlinserverblocking.generated.services.ArticleService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filter
import org.springframework.stereotype.Service

@Service
class ArticleServiceImpl : ArticleService {
    private val articleCreatedFlow = MutableSharedFlow<Article>(extraBufferCapacity = 16)
    private val articleUpdatedFlow = MutableSharedFlow<Article>(extraBufferCapacity = 16)

    override suspend fun getArticle(id: String): Article =
        Data.articles.find { it.id == id }
            ?: throw NoSuchElementException("Article not found: $id")

    override suspend fun listArticles(): List<Article> = Data.articles.toList()

    override suspend fun createArticle(input: CreateArticleInput): Article {
        val article = Article(id = Data.nextId(), title = input.title, authorId = input.authorId)
        Data.articles.add(article)
        articleCreatedFlow.emit(article)
        return article
    }

    override suspend fun updateArticle(input: UpdateArticleInput): Article {
        val article = Data.articles.find { it.id == input.id }
            ?: throw NoSuchElementException("Article not found: ${input.id}")
        val updated = input.title?.let { article.copy(title = it) } ?: article
        Data.articles[Data.articles.indexOf(article)] = updated
        articleUpdatedFlow.emit(updated)
        return updated
    }

    override fun articleCreated(): Flow<Article> = articleCreatedFlow.asSharedFlow()

    override fun articleUpdated(id: String): Flow<Article> =
        articleUpdatedFlow.asSharedFlow().filter { it.id == id }
}
