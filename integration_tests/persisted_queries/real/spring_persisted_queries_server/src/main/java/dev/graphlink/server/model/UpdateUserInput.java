package dev.graphlink.server.model;

import java.util.List;

public record UpdateUserInput(
    String name,
    String email,
    UserStatus status,
    Priority priority,
    List<String> tags
) {}
