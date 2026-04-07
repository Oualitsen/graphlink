package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.MyCoupleSchemaMappingsService;
import dev.graphlink.demo.generated.types.Car;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class MyCoupleSchemaMappingsServiceImpl implements MyCoupleSchemaMappingsService {

    @Override
    public Mono<Map<Car, Integer>> myCoupleAge(List<Car> value) {
        Map<Car, Integer> result = new HashMap<>();
        for (Car car : value) {
            int dummyAge = car.getOwner() != null && car.getOwner().getAge() != null
                    ? car.getOwner().getAge()
                    : 0;
            result.put(car, dummyAge);
        }
        return Mono.just(result);
    }
}
