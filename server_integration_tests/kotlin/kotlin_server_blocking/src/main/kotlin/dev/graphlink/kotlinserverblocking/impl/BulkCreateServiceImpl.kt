package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserverblocking.generated.services.BulkCreateService
import dev.graphlink.kotlinserverblocking.generated.types.Article
import org.springframework.stereotype.Service

@Service
class BulkCreateServiceImpl : BulkCreateService {
    override suspend fun bulkCreate(matrix: List<List<List<CreateArticleInput?>>?>?): Int {
        if (matrix == null) return 0
        var count = 0
        for (group in matrix) {
            if (group == null) continue
            for (batch in group) {
                if (batch == null) continue
                for (input in batch) {
                    if (input != null) {
                        Data.articles.add(Article(id = Data.nextId(), title = input.title, authorId = input.authorId))
                        count++
                    }
                }
            }
        }
        return count
    }

    override suspend fun validateBulkCreate(matrix: List<List<List<CreateArticleInput?>>?>?) {}
}
