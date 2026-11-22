package dev.graphlink.mappermock.persistence;

import java.util.ArrayList;
import java.util.List;

public class UserEntity {
    private String id;
    private String fullName;
    private String nick;
    private List<AddressEntity> addresses = new ArrayList<>();
    private AddressEntity home;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public String getNick() { return nick; }
    public void setNick(String nick) { this.nick = nick; }
    public List<AddressEntity> getAddresses() { return addresses; }
    public void setAddresses(List<AddressEntity> addresses) { this.addresses = addresses; }
    public AddressEntity getHome() { return home; }
    public void setHome(AddressEntity home) { this.home = home; }
}
