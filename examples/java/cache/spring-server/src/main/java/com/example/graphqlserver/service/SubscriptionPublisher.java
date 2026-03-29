package com.example.graphqlserver.service;

import com.example.graphqlserver.model.Car;
import com.example.graphqlserver.model.Owner;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

@Component
public class SubscriptionPublisher {

    private final Sinks.Many<Car> carSink = Sinks.many().multicast().onBackpressureBuffer();
    private final Sinks.Many<Owner> ownerSink = Sinks.many().multicast().onBackpressureBuffer();

    public void publishCar(Car car) {
        carSink.tryEmitNext(car);
    }

    public void publishOwner(Owner owner) {
        ownerSink.tryEmitNext(owner);
    }

    public Flux<Car> getCarFlux() {
        return carSink.asFlux();
    }

    public Flux<Owner> getOwnerFlux() {
        return ownerSink.asFlux();
    }
}
