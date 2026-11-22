package com.acme.persistence;

import java.util.List;

public class UserEntity {
  private String id;
  private String nick;
  private List<AddressEntity> addresses;
  public String getId() { return id; }
  public void setId(String id) { this.id = id; }
  public String getNick() { return nick; }
  public void setNick(String nick) { this.nick = nick; }
  public List<AddressEntity> getAddresses() { return addresses; }
  public void setAddresses(List<AddressEntity> addresses) { this.addresses = addresses; }
}
