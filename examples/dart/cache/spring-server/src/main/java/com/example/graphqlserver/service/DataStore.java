package com.example.graphqlserver.service;

import com.example.graphqlserver.model.Car;
import com.example.graphqlserver.model.Owner;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class DataStore {

    private final Map<String, Owner> owners = new ConcurrentHashMap<>();
    private final Map<String, Car> cars = new ConcurrentHashMap<>();

    public Optional<Owner> findOwner(String id) {
        Owner owner = owners.get(id);
        if (owner == null) return Optional.empty();
        // resolve cars for this owner
        List<Car> ownerCars = cars.values().stream()
                .filter(c -> id.equals(c.ownerId()))
                .toList();
        return Optional.of(new Owner(owner.id(), owner.name(), owner.email(), ownerCars));
    }

    public Optional<Car> findCar(String id) {
        return Optional.ofNullable(cars.get(id));
    }

    public Owner saveOwner(String name, String email) {
        String id = UUID.randomUUID().toString();
        Owner owner = new Owner(id, name, email, new ArrayList<>());
        owners.put(id, owner);
        return owner;
    }

    public Car saveCar(String make, String model, int year, String ownerId) {
        String id = UUID.randomUUID().toString();
        Car car = new Car(id, make, model, year, ownerId);
        cars.put(id, car);
        return car;
    }

    public int countCars() {
        return cars.size();
    }

    public Optional<String> findCarName(String id) {
        return Optional.ofNullable(cars.get(id)).map(c -> c.make() + " " + c.model());
    }
}
