package dev.graphlink.server.model;

import java.util.List;

public record NestedDefaultsEcho(
    String name,
    Address address,
    List<Address> contacts,
    List<List<Address>> matrix
) {}
