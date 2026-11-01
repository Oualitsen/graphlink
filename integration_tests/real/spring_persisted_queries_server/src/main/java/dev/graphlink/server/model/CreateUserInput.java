package dev.graphlink.server.model;

import java.util.List;

public record CreateUserInput(
    String name,
    String email,
    UserStatus status,
    Priority priority,
    AddressInput address,
    AddressInput billingAddress,
    List<String> tags,
    Integer initialScore
) {}
