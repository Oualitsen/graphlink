package dev.graphlink.server.model;

import java.util.List;

public record CreateWithDefaultsInput(
    String name,
    Role role,
    Integer age,
    Boolean isActive,
    Double score,
    String nickname,
    List<String> tags
) {}
