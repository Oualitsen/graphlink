package com.example;

import com.example.generated.inputs.RegisterAccountInput;
import com.example.generated.types.Account;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 4 — Input-only fields: password and confirmPassword exist only on the input.
 * schema: RegisterAccountInput @glMapsTo(type: "Account")
 *   email: String!
 *   displayName: String!
 *   password: String!        ← input-only, ignored in toAccount()
 *   confirmPassword: String! ← input-only, ignored in toAccount()
 *   # id missing → required param
 */
class MappingCase4Test {

    @Test
    void toAccount_mapsEmailAndDisplayName() {
        RegisterAccountInput input = new RegisterAccountInput("user@example.com", "Alice", "secret", "secret");
        Account result = input.toAccount("acc-1");

        assertThat(result.getEmail()).isEqualTo("user@example.com");
        assertThat(result.getDisplayName()).isEqualTo("Alice");
    }

    @Test
    void toAccount_assignsRequiredIdParam() {
        RegisterAccountInput input = new RegisterAccountInput("a@b.com", "Bob", "pass", "pass");
        Account result = input.toAccount("acc-99");

        assertThat(result.getId()).isEqualTo("acc-99");
    }

    @Test
    void toAccount_doesNotIncludePasswordInResult() {
        // Account has no password field — this just verifies no NPE / wrong mapping
        RegisterAccountInput input = new RegisterAccountInput("x@y.com", "Carol", "p@ssw0rd", "p@ssw0rd");

        assertThatCode(() -> input.toAccount("id-1")).doesNotThrowAnyException();
    }

    @Test
    void fromAccount_mapsEmailAndDisplayName() {
        Account account = new Account("acc-2", "b@c.com", "Dave");
        RegisterAccountInput result = RegisterAccountInput.fromAccount(account, "pw1", "pw1");

        assertThat(result.getEmail()).isEqualTo("b@c.com");
        assertThat(result.getDisplayName()).isEqualTo("Dave");
    }

    @Test
    void fromAccount_passesInputOnlyFieldsThroughAsParams() {
        Account account = new Account("acc-3", "c@d.com", "Eve");
        RegisterAccountInput result = RegisterAccountInput.fromAccount(account, "hunter2", "hunter2");

        assertThat(result.getPassword()).isEqualTo("hunter2");
        assertThat(result.getConfirmPassword()).isEqualTo("hunter2");
    }
}
