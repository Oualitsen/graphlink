package dev.graphlink.server.model;

public record Stamp(String id, String at, long big) implements Timed, Moment {}
