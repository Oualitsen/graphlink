package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.PersonService;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.List;

@Service
public class PersonServiceImpl implements PersonService {

    private static final List<Person> ALL_PERSONS = List.of(
            Person.builder().id("1").name("Alice Martin").age(30).build(),
            Person.builder().id("2").name("Bob Johnson").age(25).build(),
            Person.builder().id("3").name("Clara Smith").age(35).build(),
            Person.builder().id("4").name("David Brown").age(28).build(),
            Person.builder().id("5").name("Eva Davis").age(32).build(),
            Person.builder().id("6").name("Frank Wilson").age(45).build(),
            Person.builder().id("7").name("Grace Lee").age(27).build(),
            Person.builder().id("8").name("Henry Taylor").age(38).build(),
            Person.builder().id("9").name("Isla Anderson").age(22).build(),
            Person.builder().id("10").name("Jack Thomas").age(41).build()
    );

    @Override
    public List<Person> persons() {
        return ALL_PERSONS.subList(0, 5);
    }

    @Override
    public Flux<Person> personAdded() {
        return Flux.fromIterable(ALL_PERSONS)
                .delayElements(Duration.ofSeconds(1));
    }
}
