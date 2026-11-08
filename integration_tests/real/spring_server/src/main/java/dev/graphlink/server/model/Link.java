package dev.graphlink.server.model;

public record Link(String id, Chain next) implements Chain {}
