package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.TeamService
import dev.graphlink.kotlinserversuspend.generated.types.Team
import org.springframework.stereotype.Service

@Service
class TeamServiceImpl : TeamService {
    override suspend fun listTeams(): List<Team> = listOf(Team(id = "1", name = "Core"))
}
