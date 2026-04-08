package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreateCarInput;
import dev.graphlink.demo.generated.services.CarService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

@Service
public class CarServiceImpl implements CarService {

    @Override
    public Car car(String id) {
        Person owner = Person.builder()
                .id("1")
                .name("John Doe")
                .age(30)
                .build();
        return Car.builder()
                .id(id)
                .brand("Toyota")
                .model("Corolla")
                .owner(owner)
                .build();
    }

    @Override
    public Car createCar(CreateCarInput input) {
        Person owner = Person.builder()
                .id(input.getOwnerId())
                .name("John Doe")
                .age(30)
                .build();
        return Car.builder()
                .id("1")
                .brand(input.getBrand())
                .model(input.getModel())
                .owner(owner)
                .build();
    }
}
