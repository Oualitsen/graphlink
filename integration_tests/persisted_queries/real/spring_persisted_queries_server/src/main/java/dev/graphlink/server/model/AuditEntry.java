package dev.graphlink.server.model;

public record AuditEntry(String id, String action, String performedBy, String internalNote) {}
