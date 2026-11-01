package dev.graphlink.server.model;

// Record component names follow Java conventions; non-standard GraphQL field
// names (FirstName, last_name, USER_AGE, event_type) are mapped in the
// controller via @SchemaMapping so Spring never needs to match them by convention.
public record NormalizedFields(
        String id,
        String firstName,
        String lastName,
        int userAge,
        EventType eventType) {}
