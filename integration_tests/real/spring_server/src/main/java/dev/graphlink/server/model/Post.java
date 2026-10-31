package dev.graphlink.server.model;

public record Post(
    String id,
    String title,
    String body,
    User author,
    User coAuthor,
    int viewCount
) {}
