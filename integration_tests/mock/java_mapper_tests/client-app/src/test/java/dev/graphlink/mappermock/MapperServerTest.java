package dev.graphlink.mappermock;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import dev.graphlink.mappermock.generatedserver.mappers.UserEntityMapper;
import dev.graphlink.mappermock.generatedserver.mappers.UserMapper;
import dev.graphlink.mappermock.generatedserver.types.User;
import dev.graphlink.mappermock.generatedserver.types.UserSummary;
import dev.graphlink.mappermock.persistence.AddressEntity;
import dev.graphlink.mappermock.persistence.UserEntity;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

class MapperServerTest {

    private static AddressEntity address(String street) {
        AddressEntity a = new AddressEntity();
        a.setStreet(street);
        return a;
    }

    private static UserEntity entity() {
        UserEntity e = new UserEntity();
        e.setId("1");
        e.setFullName("Ada Lovelace");
        e.setAddresses(Arrays.asList(address("Main"), address("Side")));
        e.setHome(address("Home"));
        return e;
    }

    @Test
    void externalSourceCopiesFieldsAndMapsListAndNestedValue() {
        User user = UserEntityMapper.toUser(entity(), "anon");
        assertEquals("1", user.getId());
        assertEquals("Ada Lovelace", user.getFullName());
        assertEquals(2, user.getAddresses().size());
        assertEquals("Side", user.getAddresses().get(1).getStreet());
        assertEquals("Home", user.getHome().getStreet());
    }

    @Test
    void externalSourceNullTakesTheDefaultAndAPresentValueWins() {
        assertEquals("anon", UserEntityMapper.toUser(entity(), "anon").getNick());
        UserEntity other = new UserEntity();
        other.setId("2");
        other.setFullName("B");
        other.setNick("bee");
        User user = UserEntityMapper.toUser(other, "anon");
        assertEquals("bee", user.getNick());
        assertNull(user.getHome());
        assertEquals(0, user.getAddresses().size());
    }

    @Test
    void externalTargetIsBuiltWithNestedValues() {
        User user = UserEntityMapper.toUser(entity(), "anon");
        UserEntity back = UserMapper.toUserEntity(user);
        assertEquals("1", back.getId());
        assertEquals("Ada Lovelace", back.getFullName());
        assertEquals("anon", back.getNick());
        assertEquals(2, back.getAddresses().size());
        assertEquals("Main", back.getAddresses().get(0).getStreet());
        assertEquals("Home", back.getHome().getStreet());
    }

    @Test
    void externalTargetKeepsANullNestedValueNull() {
        UserEntity bare = new UserEntity();
        bare.setId("3");
        bare.setFullName("C");
        assertNull(UserMapper.toUserEntity(UserEntityMapper.toUser(bare, "n")).getHome());
    }

    @Test
    void mapperStyleClassRenamesAFieldForOneTarget() {
        UserSummary summary = UserMapper.toUserSummary(UserEntityMapper.toUser(entity(), "anon"));
        assertEquals("1", summary.getId());
        assertEquals("Ada Lovelace", summary.getName());
    }

    @Test
    void theGeneratedTypeHasNoInlineToMethod() throws Exception {
        assertThrows(NoSuchMethodException.class, () -> User.class.getMethod("toUserSummary"));
        assertNotNull(User.class.getMethod("getId"));
    }
}
