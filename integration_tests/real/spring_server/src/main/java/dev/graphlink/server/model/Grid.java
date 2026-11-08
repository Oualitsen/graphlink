package dev.graphlink.server.model;

import java.util.List;

public record Grid(List<List<Attachment>> cells, List<List<Entity>> rows, List<List<Attachment>> maybe) {}
