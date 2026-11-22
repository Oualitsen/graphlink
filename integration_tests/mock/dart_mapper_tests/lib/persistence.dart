class AddressEntity {
  final String street;
  AddressEntity({required this.street});
}

class UserEntity {
  final String id;
  final String fullName;
  final String? nick;
  final List<AddressEntity> addresses;
  final AddressEntity? home;
  UserEntity({required this.id, required this.fullName, this.nick, required this.addresses, this.home});
}
