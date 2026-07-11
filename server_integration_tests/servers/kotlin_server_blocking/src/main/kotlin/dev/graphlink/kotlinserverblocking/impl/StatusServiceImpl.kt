package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.StatusService
import org.springframework.stereotype.Service

@Service
class StatusServiceImpl : StatusService {
    override fun status(): String = "ok"
}
