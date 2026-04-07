package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreateCarInput;
import dev.graphlink.demo.generated.services.CarService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class CarServiceImpl implements CarService {

    private final Map<String, Car> store = new ConcurrentHashMap<>();

    public CarServiceImpl() {
        Person owner = Person.builder().id("1").name("Alice").age(30).build();
        Car c1 = Car.builder().id("1").brand("Toyota").model("Corolla").owner(owner).build();
        Car c2 = Car.builder().id("2").brand("Honda").model("Civic").owner(owner).build();
        store.put(c1.getId(), c1);
        store.put(c2.getId(), c2);
    }

    @Override
    public Mono<Car> car(String id) {
        return Mono.justOrEmpty(store.get(id));
    }

    @Override
    public Mono<Car> createCar(CreateCarInput input) {
        String id = UUID.randomUUID().toString();
        Person owner = Person.builder().id(input.getOwnerId()).build();
        Car car = Car.builder()
                .id(id)
                .brand(input.getBrand())
                .model(input.getModel())
                .owner(owner)
                .build();
        store.put(id, car);
        return Mono.just(car);
    }
}
