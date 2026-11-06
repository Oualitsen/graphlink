package dev.graphlink.server.model;

import java.util.List;

public record Article(
    String id,
    String createdBy,
    String title,
    Attachment cover,
    List<Attachment> attachments,
    List<Entity> related
) implements Entity {}
