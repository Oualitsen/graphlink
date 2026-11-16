package dev.graphlink.server.controller;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

final class SlowState {
    static final Map<String, AtomicInteger> VERSIONS = new ConcurrentHashMap<>();

    private SlowState() {}
}
