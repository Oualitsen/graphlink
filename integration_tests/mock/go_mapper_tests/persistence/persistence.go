package persistence

type AddressEntity struct {
	Street string
}

type UserEntity struct {
	Id        string
	FullName  string
	Nick      *string
	Addresses []AddressEntity
	Home      *AddressEntity
}
