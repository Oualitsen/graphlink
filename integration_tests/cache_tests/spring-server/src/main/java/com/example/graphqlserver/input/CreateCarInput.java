package com.example.graphqlserver.input;

public record CreateCarInput(String make, String model, int year, String ownerId) {
}
