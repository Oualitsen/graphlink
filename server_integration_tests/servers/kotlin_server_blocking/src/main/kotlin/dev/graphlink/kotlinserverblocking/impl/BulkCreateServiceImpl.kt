package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinserverblocking.generated.services.BulkCreateService
import org.springframework.stereotype.Service

private fun inputs(matrix: List<List<CreateArticleInput>?>?): List<CreateArticleInput> =
    matrix.orEmpty().flatMap { it.orEmpty() }

// Counts the inputs it received, so a test can see how the nested list was decoded.
@Service
class BulkCreateServiceImpl : BulkCreateService {
    override fun bulkCreate(matrix: List<List<CreateArticleInput>?>?): Int = inputs(matrix).size

    override fun validateBulkCreate(matrix: List<List<CreateArticleInput>?>?) {
        require(inputs(matrix).none { it.title == "invalid" }) { "invalid title" }
    }
}
