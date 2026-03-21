package com.example.graphqlserver.controller;

import com.example.graphqlserver.input.CreateOwnerInput;
import com.example.graphqlserver.model.Owner;
import com.example.graphqlserver.service.DataStore;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class OwnerController {

    private final DataStore dataStore;

    public OwnerController(DataStore dataStore) {
        this.dataStore = dataStore;
    }

    @QueryMapping
    public Owner getOwner(@Argument String id) {
        System.out.println("getOwner:" + id);
        return dataStore.findOwner(id).orElse(null);
    }

    @MutationMapping
    public Owner createOwner(@Argument CreateOwnerInput input) {
        return dataStore.saveOwner(input.name(), input.email());
    }
}
