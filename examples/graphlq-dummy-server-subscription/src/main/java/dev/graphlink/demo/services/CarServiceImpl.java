package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreateCarInput;
import dev.graphlink.demo.generated.services.CarService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class CarServiceImpl implements CarService {

    @Override
    public Car car(String id) {
        return Car.builder()
                .id(id)
                .brand("Tesla")
                .model("Model S")
                .owner(Person.builder()
                        .id(UUID.randomUUID().toString())
                        .name("Elon Musk")
                        .age(50)
                        .build())
                .build();
    }

    @Override
    public Car createCar(CreateCarInput input) {
        return Car.builder()
                .id(UUID.randomUUID().toString())
                .brand(input.getBrand())
                .model(input.getModel())
                .owner(Person.builder()
                        .id(input.getOwnerId())
                        .name("New Owner")
                        .age(25)
                        .build())
                .build();
    }
}
