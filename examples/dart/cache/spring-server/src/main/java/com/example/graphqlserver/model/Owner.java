package com.example.graphqlserver.model;

import java.util.List;

public record Owner(String id, String name, String email, List<Car> cars) {
}
