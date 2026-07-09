package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.enums.Priority
import dev.graphlink.kotlinserversuspend.generated.inputs.ConfigInput
import dev.graphlink.kotlinserversuspend.generated.inputs.RangeInput
import dev.graphlink.kotlinserversuspend.generated.services.AckPriorityService
import dev.graphlink.kotlinserversuspend.generated.services.ConfigService
import dev.graphlink.kotlinserversuspend.generated.services.EchoPriorityService
import dev.graphlink.kotlinserversuspend.generated.services.GreetService
import dev.graphlink.kotlinserversuspend.generated.services.RangeService
import dev.graphlink.kotlinserversuspend.generated.types.Config
import dev.graphlink.kotlinserversuspend.generated.types.Range
import org.springframework.stereotype.Service

/**
 * Default/initial-value resolvers: each simply reflects its effective input
 * back, so a client that omits a defaulted field/argument can assert the
 * schema default was applied end-to-end.
 */
@Service
class DefaultsServiceImpl :
    ConfigService, RangeService, GreetService, EchoPriorityService, AckPriorityService {

    override suspend fun resolveConfig(input: ConfigInput): Config = Config(
        pageSize = input.pageSize!!,
        ratio = input.ratio!!,
        sort = input.sort!!,
        verbose = input.verbose!!,
        priority = input.priority!!,
        tags = input.tags!!,
        empties = input.empties!!,
        note = input.note,
    )

    override suspend fun resolveRange(input: RangeInput?): Range =
        Range(min = input?.min ?: 0, max = input?.max ?: 100)

    override suspend fun greet(name: String?, times: Int?): String =
        "Hi $name!".repeat(times ?: 1)

    override suspend fun echoPriority(level: Priority?): Priority = level ?: Priority.HIGH

    override suspend fun ackPriority(level: Priority): String = "OK"
}
