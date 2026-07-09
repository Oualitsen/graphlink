package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserversuspend.generated.services.BulkCreateService
import org.springframework.stereotype.Service

@Service
class BulkCreateServiceImpl : BulkCreateService {
    override suspend fun bulkCreate(matrix: List<List<CreateArticleInput>?>?): Int = 0

    override suspend fun validateBulkCreate(matrix: List<List<CreateArticleInput>?>?) {}
}
