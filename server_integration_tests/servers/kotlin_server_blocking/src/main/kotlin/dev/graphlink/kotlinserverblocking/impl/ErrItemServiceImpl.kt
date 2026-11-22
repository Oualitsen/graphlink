package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.errors.ErrConflict
import dev.graphlink.kotlinserverblocking.generated.errors.ErrForbidden
import dev.graphlink.kotlinserverblocking.generated.errors.ErrNotFound
import dev.graphlink.kotlinserverblocking.generated.services.ErrItemService
import dev.graphlink.kotlinserverblocking.generated.types.ErrItem
import org.springframework.stereotype.Service

@Service
class ErrItemServiceImpl : ErrItemService {
    override fun errProbe(id: String): ErrItem {
        if (id == "missing") throw ErrNotFound(id = id, message = "Item $id not found")
        if (id == "forbidden") throw ErrForbidden(message = "No access")
        if (id == "boom") throw IllegalStateException("secret detail")
        return ErrItem(id = id)
    }

    override fun errRest(id: String): ErrItem {
        if (id == "missing") throw ErrNotFound(id = id, message = "Item $id not found")
        if (id == "conflict") throw ErrConflict(reason = "duplicate", message = "Conflict")
        if (id == "boom") throw IllegalStateException("secret detail")
        return ErrItem(id = id)
    }
}
