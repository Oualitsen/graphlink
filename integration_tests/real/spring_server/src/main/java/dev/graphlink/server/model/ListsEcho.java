package dev.graphlink.server.model;

import java.util.List;

public record ListsEcho(
    List<Integer> a,
    List<Integer> b,
    List<List<Integer>> c,
    List<Spelling> e,
    List<Spelling> f,
    List<Spelling> g,
    OnlyOne one
) {}
