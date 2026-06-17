package dev.graphlink.server.model;

import java.util.List;

public record NestedDefaultsInput(
    String name,
    AddressInput address,
    List<AddressInput> contacts,
    List<List<AddressInput>> matrix
) {}
