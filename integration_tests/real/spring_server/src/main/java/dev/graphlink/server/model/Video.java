package dev.graphlink.server.model;

public record Video(String id, String url, int seconds) implements Attachment {}
