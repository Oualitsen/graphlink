package dev.graphlink.server.model;

public record UserResult(String id, String name, String email) implements SearchResult {}
