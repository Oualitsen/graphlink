package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.inputs.CreatePersonInput;
import dev.graphlink.demo.generated.services.PersonService;
import dev.graphlink.demo.generated.types.Person;
import org.springframework.stereotype.Service;

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
                .id("1")
                .name(input.getName())
                .age(input.getAge())
                .build();
    }
}
