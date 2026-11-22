export interface AddressEntity {
  street: string;
}

export interface UserEntity {
  id: string;
  fullName: string;
  nick: string | null;
  addresses: AddressEntity[];
  home: AddressEntity | null;
}
