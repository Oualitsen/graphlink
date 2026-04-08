package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.PersonSchemaMappingsService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

@Service
public class PersonSchemaMappingsServiceImpl implements PersonSchemaMappingsService {

    @Override
    public Car personCarInfo(Person value) {
        return Car.builder()
                .id("1")
                .brand("Toyota")
                .model("Corolla")
                .owner(value)
                .build();
    }
}
