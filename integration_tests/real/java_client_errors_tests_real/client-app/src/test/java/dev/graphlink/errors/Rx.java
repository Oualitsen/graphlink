package dev.graphlink.errors;

final class Rx {
    private Rx() {}

    static <T> T block(T value) { return value; }
}
