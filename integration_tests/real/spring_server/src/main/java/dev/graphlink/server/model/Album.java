package dev.graphlink.server.model;

public record Album(String id, String title, int year, Listing related) implements Listing, Solo {}
