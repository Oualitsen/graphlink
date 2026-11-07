package dev.graphlink.server.model;

public record Playlist(String id, String title, int tracks, Listing related) implements Listing {}
