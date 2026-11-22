package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.errors.ErrConflict
import dev.graphlink.kotlinserversuspend.generated.errors.ErrForbidden
import dev.graphlink.kotlinserversuspend.generated.errors.ErrNotFound
import dev.graphlink.kotlinserversuspend.generated.services.ErrItemService
import dev.graphlink.kotlinserversuspend.generated.types.ErrItem
import org.springframework.stereotype.Service

@Service
class ErrItemServiceImpl : ErrItemService {
    override suspend fun errProbe(id: String): ErrItem {
        if (id == "missing") throw ErrNotFound(id = id, message = "Item $id not found")
        if (id == "forbidden") throw ErrForbidden(message = "No access")
        if (id == "boom") throw IllegalStateException("secret detail")
        return ErrItem(id = id)
    }

    override suspend fun errRest(id: String): ErrItem {
        if (id == "missing") throw ErrNotFound(id = id, message = "Item $id not found")
        if (id == "conflict") throw ErrConflict(reason = "duplicate", message = "Conflict")
        if (id == "boom") throw IllegalStateException("secret detail")
        return ErrItem(id = id)
    }
}
