package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.TeamService
import dev.graphlink.kotlinserverblocking.generated.types.Team
import org.springframework.stereotype.Service

@Service
class TeamServiceImpl : TeamService {
    override fun listTeams(): List<Team> = listOf(Team(id = "1", name = "Core"))
}
