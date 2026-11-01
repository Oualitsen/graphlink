package dev.graphlink.server.model;

import java.util.List;

public record User(
    String id,
    String name,
    String email,
    UserStatus status,
    Priority priority,
    Address address,
    Address billingAddress,
    List<String> tags,
    List<Integer> scores,
    List<Post> posts
) {}
