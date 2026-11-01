package dev.graphlink.server.model;

public record VehicleOwner(
    String id,
    String name,
    VehicleDriver driver
) {}
