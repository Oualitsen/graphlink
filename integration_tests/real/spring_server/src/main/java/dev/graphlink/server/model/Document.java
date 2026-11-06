package dev.graphlink.server.model;

public record Document(String id, String url, int pages) implements Attachment {}
