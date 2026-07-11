package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.DeleteArticleService
import org.springframework.stereotype.Service

@Service
class DeleteArticleServiceImpl : DeleteArticleService {
    override suspend fun deleteArticle(id: String): Boolean = Data.articles.removeAll { it.id == id }
}
