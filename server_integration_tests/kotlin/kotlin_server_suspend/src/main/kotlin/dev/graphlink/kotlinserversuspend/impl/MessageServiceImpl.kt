package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.MessageReadSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.MessageService
import dev.graphlink.kotlinserversuspend.generated.types.Message
import org.springframework.stereotype.Service

@Service
class MessageServiceImpl : MessageService, MessageReadSchemaMappingsService {

    override suspend fun getMessageReadList(): List<Message?>? = listOf(
        Message(id = "m1", content = "hello"),
        Message(id = "m2", content = "world"),
    )

    override suspend fun messageReadRead(value: List<Message>): Map<Message, Boolean> {
        val result = LinkedHashMap<Message, Boolean>()
        for (m in value) {
            result[m] = m.id.endsWith("1")
        }
        return result
    }
}
