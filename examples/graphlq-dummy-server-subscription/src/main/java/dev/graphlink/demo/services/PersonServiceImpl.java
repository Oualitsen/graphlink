package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreatePersonInput;
import dev.graphlink.demo.generated.services.PersonService;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.UUID;

@Service
public class PersonServiceImpl implements PersonService {

    @Override
    public Person person(String id) {
        return Person.builder()
                .id(id)
                .name("John Doe")
                .age(30)
                .build();
    }

    @Override
    public Person createPerson(CreatePersonInput input) {
        return Person.builder()
                .id(UUID.randomUUID().toString())
                .name(input.getName())
                .age(input.getAge())
                .build();
    }

    @Override
    public Flux<Person> personCreated() {
        return Flux.interval(Duration.ofSeconds(1))
                .take(10)
                .map(i -> Person.builder()
                        .id(UUID.randomUUID().toString())
                        .name("Person " + i)
                        .age(20 + i.intValue())
                        .build());
    }
}
