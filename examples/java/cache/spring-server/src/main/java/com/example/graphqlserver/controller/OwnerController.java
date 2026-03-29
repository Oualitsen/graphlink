package com.example.graphqlserver.controller;

import com.example.graphqlserver.input.CreateOwnerInput;
import com.example.graphqlserver.model.Owner;
import com.example.graphqlserver.service.DataStore;
import com.example.graphqlserver.service.SubscriptionPublisher;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class OwnerController {

    private final DataStore dataStore;
    private final SubscriptionPublisher publisher;

    public OwnerController(DataStore dataStore, SubscriptionPublisher publisher) {
        this.dataStore = dataStore;
        this.publisher = publisher;
    }

    @QueryMapping
    public Owner getOwner(@Argument String id) {
        System.out.println("getting owner with id = " + id);
        return dataStore.findOwner(id).orElse(null);
    }

    @MutationMapping
    public Owner createOwner(@Argument CreateOwnerInput input) {
        Owner owner = dataStore.saveOwner(input.name(), input.email());
        publisher.publishOwner(owner);
        return owner;
    }
}
