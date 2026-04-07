package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreatePersonInput;
import dev.graphlink.demo.generated.services.PersonService;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class PersonServiceImpl implements PersonService {

    private final Map<String, Person> store = new ConcurrentHashMap<>();

    public PersonServiceImpl() {
        Person p1 = Person.builder().id("1").name("Alice").age(30).build();
        Person p2 = Person.builder().id("2").name("Bob").age(25).build();
        store.put(p1.getId(), p1);
        store.put(p2.getId(), p2);
    }

    @Override
    public Mono<Person> person(String id) {
        return Mono.justOrEmpty(store.get(id));
    }

    @Override
    public Mono<Person> createPerson(CreatePersonInput input) {
        String id = UUID.randomUUID().toString();
        Person person = Person.builder()
                .id(id)
                .name(input.getName())
                .age(input.getAge())
                .build();
        store.put(id, person);
        return Mono.just(person);
    }
}
