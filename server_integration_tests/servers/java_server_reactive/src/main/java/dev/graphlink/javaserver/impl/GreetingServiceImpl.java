package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.GreetingService;
import dev.graphlink.javaserver.generated.types.Greeting;
import graphql.GraphQLContext;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

@Service
public class GreetingServiceImpl implements GreetingService {

    private final Sinks.Many<Greeting> greetingReceivedSink = Sinks.many().multicast().directBestEffort();

    private Greeting buildGreeting(String name, String marker) {
        return Greeting.builder()
                .id("1")
                .message("Hello, " + name + (marker != null ? marker : ""))
                .build();
    }

    @Override
    public Mono<Greeting> greetIntercepted(String name, GraphQLContext context) {
        return Mono.just(buildGreeting(name, context.get("marker")));
    }

    @Override
    public Mono<Greeting> greetPlain(String name) {
        return Mono.just(buildGreeting(name, null));
    }

    @Override
    public Mono<Greeting> sendGreeting(String name) {
        Greeting greeting = buildGreeting(name, null);
        greetingReceivedSink.tryEmitNext(greeting);
        return Mono.just(greeting);
    }

    // `runBefore` (returning Mono<Void>, chained via .then()) has already
    // completed by the time this method runs, so the marker is captured
    // once, here, and baked into every subsequently emitted greeting for the
    // lifetime of this subscription.
    @Override
    public Flux<Greeting> greetingReceived(GraphQLContext context) {
        String marker = context.get("marker");
        return greetingReceivedSink.asFlux()
                .map(g -> marker != null
                        ? Greeting.builder().id(g.getId()).message(g.getMessage() + marker).build()
                        : g);
    }
}
