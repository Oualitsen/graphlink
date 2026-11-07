package dev.graphlink.server.model;

public record PhaseProbe(Phase single, Phase maybe, java.util.List<Phase> list, java.util.List<Phase> nullableList) {}
