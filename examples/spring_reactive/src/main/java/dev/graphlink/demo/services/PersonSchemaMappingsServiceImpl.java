package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.PersonSchemaMappingsService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class PersonSchemaMappingsServiceImpl implements PersonSchemaMappingsService {

    @Override
    public Mono<Car> personCar(Person value) {
        Car car = Car.builder()
                .id("car-" + value.getId())
                .brand("Toyota")
                .model("Corolla")
                .owner(value)
                .build();
        return Mono.just(car);
    }

    @Override
    public Mono<Car> personCar2(Person value) {
        Car car = Car.builder()
                .id("car2-" + value.getId())
                .brand("Honda")
                .model("Civic")
                .owner(value)
                .build();
        return Mono.just(car);
    }
}
