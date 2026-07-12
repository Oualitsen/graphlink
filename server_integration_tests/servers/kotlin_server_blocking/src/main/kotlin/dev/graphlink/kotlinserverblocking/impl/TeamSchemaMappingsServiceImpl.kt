package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.TeamSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.types.Member
import dev.graphlink.kotlinserverblocking.generated.types.Team
import graphql.GraphQLContext
import org.springframework.stereotype.Service

private val membersByTeamId: Map<String, List<Member>> = mapOf(
    "1" to listOf(Member(id = "1", name = "Ada"), Member(id = "2", name = "Grace")),
)

@Service
class TeamSchemaMappingsServiceImpl : TeamSchemaMappingsService {
    // Access control lives entirely in InterceptorImpl.runBefore (throw to
    // deny, return to allow) — by the time this method runs, the caller was
    // already let through, so it just returns the real data.
    override fun teamMembers(role: String, value: Team, graphQLContext: GraphQLContext): List<Member> =
        membersByTeamId[value.id] ?: emptyList()
}
