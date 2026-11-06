package dev.graphlink.server.model;

public record Comment(String id, String createdBy, String text, Entity parent) implements Entity {}
