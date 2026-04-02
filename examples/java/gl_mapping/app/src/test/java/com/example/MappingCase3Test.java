package com.example;

import com.example.generated.inputs.CreateUserInput;
import com.example.generated.types.User;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 3 — Nullability mismatch: nullable source → non-null target.
 * schema: CreateUserInput @glMapsTo(type: "User")
 *   username: String!
 *   role: String    ← nullable in input, non-null in User → defaultRole param
 *   # id missing → required param
 */
class MappingCase3Test {

    @Test
    void toUser_usesActualRoleWhenPresent() {
        CreateUserInput input = new CreateUserInput("alice", "admin");
        User result = input.toUser("u-1", "guest");

        assertThat(result.getRole()).isEqualTo("admin"); // actual value wins over default
    }

    @Test
    void toUser_fallsBackToDefaultRoleWhenRoleIsNull() {
        CreateUserInput input = new CreateUserInput("bob", null); // role is nullable
        User result = input.toUser("u-2", "viewer");

        assertThat(result.getRole()).isEqualTo("viewer"); // null → use default
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

        assertThat(result.getId()).isEqualTo("user-99");
        assertThat(result.getUsername()).isEqualTo("dave");
    }

    @Test
    void fromUser_mapsUsernameAndRole() {
        User user = new User("u-5", "eve", "superadmin");
        CreateUserInput result = CreateUserInput.fromUser(user);

        assertThat(result.getUsername()).isEqualTo("eve");
        assertThat(result.getRole()).isEqualTo("superadmin");
    }
}
