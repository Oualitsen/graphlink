package com.example;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import com.example.generated.interfaces.*;
import com.example.generated.inputs.*;
import com.example.generated.types.*;
import com.example.generated.enums.*;
import com.example.generated.client.*;

public class Main {

    private static final String SERVER_URL = "http://localhost:8080/graphql";

    public static void main(String[] args) throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        HttpClient http = HttpClient.newHttpClient();

        GraphLinkJsonEncoder encoder = obj -> {
            try {
                return mapper.writeValueAsString(obj);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };
        GraphLinkJsonDecoder decoder = json -> {
            try {
                return mapper.readValue(json, Map.class);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };

        GraphLinkClientAdapter adapter = payload -> {
            try {
                HttpRequest request = HttpRequest.newBuilder()
                        .uri(URI.create(SERVER_URL))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(payload))
                        .build();
                HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() != 200) {
                    throw new RuntimeException("Server error: " + response.statusCode());
                }
                return response.body();
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        };

        GraphLinkClient client = new GraphLinkClient(adapter, encoder, decoder, null);

        // --- create a car ---
        var created = client.mutations.createCar(CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build());
        String carId = created.getCreateCar().getId();
        System.out.println("Created car: " + carId);

        // --- first fetch — hits the server ---
        var first = client.queries.getCar(carId);
        System.out.println("First fetch (server): " + first.getGetCar().getMake() + " " + first.getGetCar().getModel());

        // --- second fetch — should hit cache ---
        var second = client.queries.getCar(carId);
        System.out.println("Second fetch (cache): " + second.getGetCar().getMake() + " " + second.getGetCar().getModel());
    }
}
