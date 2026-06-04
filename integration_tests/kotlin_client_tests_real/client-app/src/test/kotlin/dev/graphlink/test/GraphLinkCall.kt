package dev.graphlink.test

data class GraphLinkCall(
    val operationName: String?,
    val variables: Map<String, Any?>,
    val rawPayload: String,
)
