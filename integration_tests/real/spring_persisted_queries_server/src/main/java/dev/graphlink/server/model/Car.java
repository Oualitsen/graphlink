package dev.graphlink.server.model;

public record Car(
    String id,
    String model,
    VehicleOwner owner
) implements Vehicle {}
