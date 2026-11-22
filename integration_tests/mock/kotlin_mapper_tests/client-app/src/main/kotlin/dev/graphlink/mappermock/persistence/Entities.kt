package dev.graphlink.mappermock.persistence

class AddressEntity {
    var street: String = ""
}

class UserEntity {
    var id: String = ""
    var fullName: String = ""
    var nick: String? = null
    var addresses: List<AddressEntity> = emptyList()
    var home: AddressEntity? = null
}
