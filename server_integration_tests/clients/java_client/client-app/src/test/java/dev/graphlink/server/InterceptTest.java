package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.client.GraphLinkException;
import dev.graphlink.server.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.server.generated.inputs.ListTeamsFieldArgs;
import dev.graphlink.server.generated.types.GreetingReceivedResponse;
import dev.graphlink.server.generated.types.Member;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

public class InterceptTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Test
    void greetInterceptedAppendsTheRunBeforeMarkerToTheNameArgument() {
        var res = client.queries.greetIntercepted("Ada");
        assertEquals("Hello, Ada(runBefore)", res.getGreetIntercepted().getMessage());
    }

    @Test
    void greetPlainIsNotInterceptedNoMarkerAppended() {
        var res = client.queries.greetPlain("Ada");
        assertEquals("Hello, Ada", res.getGreetPlain().getMessage());
    }

    @Test
    void greetingReceivedBakesTheMarkerIntoEveryEmittedGreeting() throws Exception {
        CompletableFuture<GreetingReceivedResponse> eventFuture = new CompletableFuture<>();
        client.subscriptions.greetingReceived(new GraphLinkSubscriptionListener<GreetingReceivedResponse>() {
            @Override
            public void onMessage(GreetingReceivedResponse response) {
                eventFuture.complete(response);
            }

            @Override
            public void onError(GraphLinkException error) {
                eventFuture.completeExceptionally(error);
            }
        });

        Thread.sleep(300);

        client.mutations.sendGreeting("Ada");

        var event = eventFuture.get(10, TimeUnit.SECONDS);
        assertEquals("Hello, Ada(runBefore)", event.getGreetingReceived().getMessage());
    }

    @Test
    void teamMembersInterceptedMappingAllowsRoleAuth() {
        var res = client.queries.listTeams(new ListTeamsFieldArgs("auth"));
        var members = res.getListTeams().get(0).getMembers().stream().map(Member::getName).collect(Collectors.toSet());
        assertEquals(Set.of("Ada", "Grace"), members);
    }

    @Test
    void teamMembersInterceptedMappingDeniesAnyOtherRole() {
        assertThrows(GraphLinkException.class, () -> client.queries.listTeams(new ListTeamsFieldArgs("wrong")));
    }
}
