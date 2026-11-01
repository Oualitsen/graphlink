package dev.graphlink.server.model;

public record Bike(
    String id,
    String brand,
    VehicleOwner owner
) implements Vehicle {}
