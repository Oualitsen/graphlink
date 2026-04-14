package com.example;

import com.example.generated.inputs.CreateUserInput;
import com.example.generated.types.User;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 3 — Nullability mismatch: nullable source → non-null target.
 * role is nullable in input, non-null in User → defaultRole param.
 */
class MappingCase3Test {

    @Test
    void toUser_usesActualRoleWhenPresent() {
        CreateUserInput input = new CreateUserInput("alice", "admin");
        User result = input.toUser("u-1", "guest");

        assertThat(result.role()).isEqualTo("admin");
    }

    @Test
    void toUser_fallsBackToDefaultRoleWhenRoleIsNull() {
        CreateUserInput input = new CreateUserInput("bob", null);
        User result = input.toUser("u-2", "viewer");

        assertThat(result.role()).isEqualTo("viewer");
    }

    @Test
    void toUser_withNullRole_doesNotThrow() {
        CreateUserInput input = new CreateUserInput("carol", null);

        assertThatCode(() -> input.toUser("u-3", "fallback")).doesNotThrowAnyException();
    }

    @Test
    void toUser_assignsRequiredIdParam() {
        CreateUserInput input = new CreateUserInput("dave", "mod");
        User result = input.toUser("user-99", "guest");

        assertThat(result.id()).isEqualTo("user-99");
        assertThat(result.username()).isEqualTo("dave");
    }

    @Test
    void fromUser_mapsUsernameAndRole() {
        User user = new User("u-5", "eve", "superadmin");
        CreateUserInput result = CreateUserInput.fromUser(user);

        assertThat(result.username()).isEqualTo("eve");
        assertThat(result.role()).isEqualTo("superadmin");
    }
}
