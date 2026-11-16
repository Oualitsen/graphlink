package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserversuspend.generated.services.BulkCreateService
import org.springframework.stereotype.Service

private fun inputs(matrix: List<List<CreateArticleInput>?>?): List<CreateArticleInput> =
    matrix.orEmpty().flatMap { it.orEmpty() }

// Counts the inputs it received, so a test can see how the nested list was decoded.
@Service
class BulkCreateServiceImpl : BulkCreateService {
    override suspend fun bulkCreate(matrix: List<List<CreateArticleInput>?>?): Int = inputs(matrix).size

    override suspend fun validateBulkCreate(matrix: List<List<CreateArticleInput>?>?) {
        require(inputs(matrix).none { it.title == "invalid" }) { "invalid title" }
    }
}
