public struct AddressEntity {
    public var street: String
    public init(street: String) { self.street = street }
}

public struct UserEntity {
    public var id: String
    public var fullName: String
    public var nick: String?
    public var addresses: [AddressEntity]
    public var home: AddressEntity?

    public init(id: String, fullName: String, nick: String? = nil, addresses: [AddressEntity] = [], home: AddressEntity? = nil) {
        self.id = id
        self.fullName = fullName
        self.nick = nick
        self.addresses = addresses
        self.home = home
    }
}
