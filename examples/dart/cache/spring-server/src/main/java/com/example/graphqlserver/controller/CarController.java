package com.example.graphqlserver.controller;

import com.example.graphqlserver.input.CreateCarInput;
import com.example.graphqlserver.model.Car;
import com.example.graphqlserver.service.DataStore;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class CarController {

    private final DataStore dataStore;

    public CarController(DataStore dataStore) {
        this.dataStore = dataStore;
    }

    @QueryMapping
    public Car getCar(@Argument String id) {
        System.out.println("getting car with id = " + id);
        return dataStore.findCar(id).orElse(null);
    }

    @QueryMapping
    public int getCarsCount() {
        System.out.println("getting cars count");
        return dataStore.countCars();
    }

    @QueryMapping
    public String getCarName(@Argument String id) {
        System.out.println("getting car name for id = " + id);
        return dataStore.findCarName(id).orElse(null);
    }

    @MutationMapping
    public Car createCar(@Argument CreateCarInput input) {
        return dataStore.saveCar(input.make(), input.model(), input.year(), input.ownerId());
    }
}
