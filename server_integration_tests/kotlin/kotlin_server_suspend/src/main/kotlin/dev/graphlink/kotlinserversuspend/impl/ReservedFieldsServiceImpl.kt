package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.enums.Keyword
import dev.graphlink.kotlinserversuspend.generated.inputs.ReservedInput
import dev.graphlink.kotlinserversuspend.generated.services.ReservedFieldsService
import dev.graphlink.kotlinserversuspend.generated.types.Class
import dev.graphlink.kotlinserversuspend.generated.types.ReservedFields
import dev.graphlink.kotlinserversuspend.generated.types.Secret_
import org.springframework.stereotype.Service

@Service
class ReservedFieldsServiceImpl : ReservedFieldsService {

    private fun base(): ReservedFields = ReservedFields(
        id = "r1",
        class_ = "cls",
        return_ = 42,
        new = true,
        default = "def",
        is_ = "yes",
        in_ = "inside",
        with = "w",
        int = 7,
        synchronized = false,
        native = "n",
        kind = Keyword.CLASS,
        nested = Class(id = "c1", value = "v"),
        secret = Secret_(id = "s1", token = "tok"),
    )

    override suspend fun reserved(): ReservedFields = base()

    override suspend fun switch(class_: String, return_: Int?): ReservedFields =
        base().copy(class_ = class_, return_ = return_ ?: 0)

    override suspend fun echoReserved(input: ReservedInput): ReservedFields = base().copy(
        class_ = input.class_,
        return_ = input.return_ ?: -1,
        default = input.default ?: "none",
    )
}
