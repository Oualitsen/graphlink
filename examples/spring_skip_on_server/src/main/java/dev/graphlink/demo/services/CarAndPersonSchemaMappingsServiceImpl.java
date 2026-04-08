package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.CarAndPersonSchemaMappingsService;
import dev.graphlink.demo.generated.types.Car;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class CarAndPersonSchemaMappingsServiceImpl implements CarAndPersonSchemaMappingsService {

    @Override
    public Map<Car, Person> carAndPersonPerson(List<Car> value) {
        Map<Car, Person> result = new HashMap<>();
        for (Car car : value) {
            Person person = Person.builder()
                    .id("1")
                    .name("John Doe")
                    .age(30)
                    .build();
            result.put(car, person);
        }
        return result;
    }
}
