package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.CollideService
import dev.graphlink.kotlinserversuspend.generated.types.Collide
import org.springframework.stereotype.Service

@Service
class CollideServiceImpl : CollideService {
    // The two colliding wire fields (`class` and `class_`) carry distinct
    // values so the round-trip can prove they stayed separate identifiers.
    override suspend fun collide(): Collide = Collide(id = "1", class_2 = "A", class2 = "B")
}
