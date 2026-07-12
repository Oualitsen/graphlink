package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.TeamService;
import dev.graphlink.javaserver.generated.types.Team;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.util.List;

@Service
public class TeamServiceImpl implements TeamService {

    static final List<Team> TEAMS = List.of(Team.builder().id("1").name("Core").build());

    @Override
    public Flux<Team> listTeams() {
        return Flux.fromIterable(TEAMS);
    }
}
