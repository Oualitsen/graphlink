package dev.graphlink.server.model;

// Wire values are non-standard casing on purpose — this exercises client-side
// identifier normalization (Dart: inProgress, Java/Kotlin: IN_PROGRESS, TS: InProgress).
public enum EventType {
    pending,
    in_progress,
    completed_ok
}
