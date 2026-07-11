package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.CollideService;
import dev.graphlink.javaserver.generated.types.Collide;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class CollideServiceImpl implements CollideService {

    @Override
    public Mono<Collide> collide() {
        // The two colliding wire fields (`class` and `class_`) carry distinct
        // values so the round-trip can prove they stayed separate identifiers.
        return Mono.just(Collide.builder().id("1").class_2("A").class2("B").build());
    }
}
