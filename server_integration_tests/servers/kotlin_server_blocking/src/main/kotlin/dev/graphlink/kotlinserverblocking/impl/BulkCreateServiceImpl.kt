package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserverblocking.generated.services.BulkCreateService
import org.springframework.stereotype.Service

@Service
class BulkCreateServiceImpl : BulkCreateService {
    override fun bulkCreate(matrix: List<List<CreateArticleInput>?>?): Int = 0

    override fun validateBulkCreate(matrix: List<List<CreateArticleInput>?>?) {}
}
