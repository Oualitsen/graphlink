package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput

object Helpers {
    fun newClient(server: ApqServer): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(server.post, server.get, MockWebSocketAdapter(), MockMultipartAdapter(), codec, codec)
    }

    fun hashOf(request: Map<String, Any?>): Map<*, *> =
        (request["extensions"] as Map<*, *>)["persistedQuery"] as Map<*, *>

    val createUserInput = CreateUserInput(
        name = "Alice",
        email = "a@test.com",
        status = UserStatus.ACTIVE,
        address = AddressInput("s", "c", "x"),
    )
}
