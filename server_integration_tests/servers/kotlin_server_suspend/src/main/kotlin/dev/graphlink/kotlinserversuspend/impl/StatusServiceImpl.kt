package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.StatusService
import org.springframework.stereotype.Service

@Service
class StatusServiceImpl : StatusService {
    override suspend fun status(): String = "ok"
}
