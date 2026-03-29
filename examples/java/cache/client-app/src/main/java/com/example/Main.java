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
    private static final String WS_URL = "ws://localhost:8080/graphql";

    public static void main(String[] args) throws Exception {


        GraphLinkClient client = new GraphLinkClient(SERVER_URL, WS_URL);

        client.subscriptions.onCarCreated(r -> {
            System.out.println("Car created " + r.getOnCarCreated().getId());
        });

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

        Thread.sleep(5000);
    }
}
