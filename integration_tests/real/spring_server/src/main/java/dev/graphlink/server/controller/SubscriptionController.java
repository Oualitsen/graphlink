package dev.graphlink.server.controller;

import dev.graphlink.server.DataFixtures;
import dev.graphlink.server.model.ListsEcho;
import dev.graphlink.server.model.ListsInput;
import dev.graphlink.server.model.OnlyOne;
import dev.graphlink.server.model.Spelling;
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

    @SubscriptionMapping
    public Flux<ListsEcho> subEchoArgs(
        @Argument List<Integer> a,
        @Argument List<Integer> b,
        @Argument List<List<Integer>> c,
        @Argument List<Spelling> e,
        @Argument List<Spelling> f,
        @Argument List<Spelling> g,
        @Argument OnlyOne one) {
        return Flux.just(new ListsEcho(a, b, c, e, f, g, one));
    }

    @SubscriptionMapping
    public Flux<ListsEcho> subEchoInput(@Argument ListsInput input) {
        return Flux.just(new ListsEcho(input.a(), input.b(), input.c(), input.e(), input.f(), input.g(), input.one()));
    }

    @SubscriptionMapping
    public Flux<Integer> finiteTicks(@Argument int count) {
        return Flux.range(1, count);
    }

    @SubscriptionMapping
    public Flux<Integer> flakyTicks(@Argument int failAfter) {
        return Flux.range(1, failAfter).concatWith(Flux.error(new IllegalStateException("flaky stream failed")));
    }
}
