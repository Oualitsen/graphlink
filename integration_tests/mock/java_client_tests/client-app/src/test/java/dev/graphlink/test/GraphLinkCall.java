package dev.graphlink.test;

import java.util.Map;

/**
 * One recorded outgoing GraphQL request captured by MockAdapter.
 */
public record GraphLinkCall(
        String operationName,
        Map<String, Object> variables,
        String rawPayload
) {}
