package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.TeamSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Member;
import dev.graphlink.javaserver.generated.types.Team;
import graphql.GraphQLContext;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.util.List;
import java.util.Map;

@Service
public class TeamSchemaMappingsServiceImpl implements TeamSchemaMappingsService {

    static final Map<String, List<Member>> MEMBERS_BY_TEAM_ID = Map.of(
            "1", List.of(
                    Member.builder().id("1").name("Ada").build(),
                    Member.builder().id("2").name("Grace").build()));

    // Access control lives entirely in InterceptorImpl.runBefore (throw to
    // deny, return to allow) — by the time this method runs, the caller was
    // already let through, so it just returns the real data.
    @Override
    public Flux<Member> teamMembers(String role, Team value, GraphQLContext context) {
        return Flux.fromIterable(MEMBERS_BY_TEAM_ID.getOrDefault(value.getId(), List.of()));
    }
}
