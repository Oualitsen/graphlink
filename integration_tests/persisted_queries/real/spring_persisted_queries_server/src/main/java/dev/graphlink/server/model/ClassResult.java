package dev.graphlink.server.model;

// The GraphQL field is `class` (a Java keyword), so the record component is named
// `classValue` and the `class` field is served via @SchemaMapping in the
// controller. Tests that the wire field name `class` round-trips correctly.
public record ClassResult(String id, String classValue) {}
