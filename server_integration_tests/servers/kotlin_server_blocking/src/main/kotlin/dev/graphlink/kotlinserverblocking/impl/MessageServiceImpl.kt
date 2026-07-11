package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.MessageReadSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.MessageService
import dev.graphlink.kotlinserverblocking.generated.types.Message
import org.springframework.stereotype.Service

@Service
class MessageServiceImpl : MessageService, MessageReadSchemaMappingsService {

    override fun getMessageReadList(): List<Message?>? = listOf(
        Message(id = "m1", content = "hello"),
        Message(id = "m2", content = "world"),
    )

    override fun messageReadRead(value: List<Message>): Map<Message, Boolean> {
        val result = LinkedHashMap<Message, Boolean>()
        for (m in value) {
            result[m] = m.id.endsWith("1")
        }
        return result
    }
}
