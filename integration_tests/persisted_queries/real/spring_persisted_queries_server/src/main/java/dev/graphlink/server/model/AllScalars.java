package dev.graphlink.server.model;

public record AllScalars(
    String id,
    String strVal,
    int intVal,
    double floatVal,
    boolean boolVal,
    String nullableStr,
    Integer nullableInt,
    Double nullableFloat,
    Boolean nullableBool,
    String nullableId
) {}
