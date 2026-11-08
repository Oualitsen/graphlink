package dev.graphlink.server.model;

import java.util.List;

public record Span(String id, String at, String until, String opaque, List<String> dts) implements Timed, Moment {}
