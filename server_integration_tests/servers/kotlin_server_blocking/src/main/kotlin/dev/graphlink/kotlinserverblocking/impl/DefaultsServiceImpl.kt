package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.enums.Priority
import dev.graphlink.kotlinserverblocking.generated.inputs.ConfigInput
import dev.graphlink.kotlinserverblocking.generated.inputs.RangeInput
import dev.graphlink.kotlinserverblocking.generated.services.AckPriorityService
import dev.graphlink.kotlinserverblocking.generated.services.ConfigService
import dev.graphlink.kotlinserverblocking.generated.services.EchoPriorityService
import dev.graphlink.kotlinserverblocking.generated.services.GreetService
import dev.graphlink.kotlinserverblocking.generated.services.RangeService
import dev.graphlink.kotlinserverblocking.generated.types.Config
import dev.graphlink.kotlinserverblocking.generated.types.Range
import org.springframework.stereotype.Service

/**
 * Default/initial-value resolvers: each simply reflects its effective input
 * back, so a client that omits a defaulted field/argument can assert the
 * schema default was applied end-to-end.
 */
@Service
class DefaultsServiceImpl :
    ConfigService, RangeService, GreetService, EchoPriorityService, AckPriorityService {

    override fun resolveConfig(input: ConfigInput): Config = Config(
        pageSize = input.pageSize!!,
        ratio = input.ratio!!,
        sort = input.sort!!,
        verbose = input.verbose!!,
        priority = input.priority!!,
        tags = input.tags!!,
        empties = input.empties!!,
        note = input.note,
    )

    override fun resolveRange(input: RangeInput?): Range =
        Range(min = input?.min ?: 0, max = input?.max ?: 100)

    override fun greet(name: String?, times: Int?): String =
        "Hi $name!".repeat(times ?: 1)

    override fun echoPriority(level: Priority?): Priority = level ?: Priority.HIGH

    override fun ackPriority(level: Priority): String = "OK"
}
