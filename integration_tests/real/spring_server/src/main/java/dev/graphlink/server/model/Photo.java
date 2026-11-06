package dev.graphlink.server.model;

public record Photo(String id, String url, int width) implements Attachment, Shareable {}
