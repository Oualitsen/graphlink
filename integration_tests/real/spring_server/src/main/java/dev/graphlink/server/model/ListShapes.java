package dev.graphlink.server.model;

import java.util.List;

public record ListShapes(
    List<Integer> a,
    List<Integer> b,
    List<Integer> c,
    List<Integer> d,
    List<List<Integer>> e,
    List<List<Integer>> f,
    List<Spelling> g,
    List<Photo> h,
    List<Attachment> i,
    List<Entity> j
) {}
