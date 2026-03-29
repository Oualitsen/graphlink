package com.example.graphqlserver.controller;

import com.example.graphqlserver.model.Car;
import com.example.graphqlserver.model.Owner;
import com.example.graphqlserver.service.SubscriptionPublisher;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

@Controller
public class SubscriptionController {

    private final SubscriptionPublisher publisher;

    public SubscriptionController(SubscriptionPublisher publisher) {
        this.publisher = publisher;
    }

    @SubscriptionMapping
    public Flux<Car> onCarCreated() {
        return publisher.getCarFlux();
    }

    @SubscriptionMapping
    public Flux<Owner> onOwnerCreated() {
        return publisher.getOwnerFlux();
    }
}
