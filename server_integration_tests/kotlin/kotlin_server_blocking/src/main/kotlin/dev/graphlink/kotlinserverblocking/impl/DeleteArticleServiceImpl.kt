package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.DeleteArticleService
import org.springframework.stereotype.Service

@Service
class DeleteArticleServiceImpl : DeleteArticleService {
    override suspend fun deleteArticle(id: String): Boolean =
        Data.articles.removeIf { it.id == id }
}
