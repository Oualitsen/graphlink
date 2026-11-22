import com.acme.mappers.UserEntityMapper;
import com.acme.mappers.UserMapper;
import com.acme.persistence.AddressEntity;
import com.acme.persistence.UserEntity;
import com.acme.types.User;
import java.util.List;

public class Main {
  public static void main(String[] args) {
    AddressEntity address = new AddressEntity();
    address.setStreet("Main street");
    UserEntity entity = new UserEntity();
    entity.setId("1");
    entity.setAddresses(List.of(address));

    User user = UserEntityMapper.toUser(entity, "anonymous");
    check("1".equals(user.getId()), "id");
    check("anonymous".equals(user.getNick()), "nick default");
    check("Main street".equals(user.getAddresses().get(0).getStreet()), "nested list");

    UserEntity back = UserMapper.toUserEntity(user);
    check("1".equals(back.getId()), "id back");
    check("anonymous".equals(back.getNick()), "nick back");
    check(back.getAddresses().size() == 1, "list back");
    System.out.println("external mappers: ok");
  }

  static void check(boolean condition, String what) {
    if (!condition) throw new AssertionError(what);
  }
}
