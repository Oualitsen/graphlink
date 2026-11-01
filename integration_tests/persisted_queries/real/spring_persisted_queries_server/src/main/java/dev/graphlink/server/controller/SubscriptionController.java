package dev.graphlink.server.controller;

import dev.graphlink.server.DataFixtures;
import dev.graphlink.server.model.User;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.SubscriptionMapping;
import org.springframework.stereotype.Controller;
import reactor.core.publisher.Flux;

import java.time.Duration;
import java.util.List;

@Controller
public class SubscriptionController {

    @SubscriptionMapping
    public Flux<User> userCreated() {
        return Flux.just(DataFixtures.ALICE, DataFixtures.BOB);
    }

    @SubscriptionMapping
    public Flux<List<User>> userCreateds(@Argument List<String> ids) {
        List<User> matching = ids.stream()
                .map(DataFixtures::userById)
                .filter(u -> u != null)
                .toList();
        return Flux.just(matching);
    }

    @SubscriptionMapping
    public Flux<User> userStatusChanged(@Argument String userId) {
        User user = DataFixtures.userById(userId);
        if (user == null) user = DataFixtures.ALICE;
        return Flux.just(user);
    }

    @SubscriptionMapping
    public Flux<Integer> counterTick() {
        return Flux.interval(Duration.ofSeconds(1)).map(i -> i.intValue() + 1);
    }

}
