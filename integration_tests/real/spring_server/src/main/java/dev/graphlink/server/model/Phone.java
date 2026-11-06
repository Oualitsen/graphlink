package dev.graphlink.server.model;

public record Phone(String id, int size, String model) implements Gadget, Shareable {}
