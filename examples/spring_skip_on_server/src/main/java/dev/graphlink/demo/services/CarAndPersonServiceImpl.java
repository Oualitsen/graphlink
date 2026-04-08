package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.CarAndPersonService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

@Service
public class CarAndPersonServiceImpl implements CarAndPersonService {

    @Override
    public Car getCarPerson(String carId, String personId) {
        Person owner = Person.builder()
                .id(personId)
                .name("John Doe")
                .age(30)
                .build();
        return Car.builder()
                .id(carId)
                .brand("Toyota")
                .model("Corolla")
                .owner(owner)
                .build();
    }
}
