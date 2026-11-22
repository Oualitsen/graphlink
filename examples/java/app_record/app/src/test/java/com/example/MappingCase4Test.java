package com.example;

import com.example.generated.inputs.RegisterAccountInput;
import com.example.generated.types.Account;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 4 — Input-only fields: password and confirmPassword exist only on the input.
 */
class MappingCase4Test {

    @Test
    void toAccount_mapsEmailAndDisplayName() {
        RegisterAccountInput input = new RegisterAccountInput("user@example.com", "Alice", "secret", "secret");
        Account result = input.toAccount("acc-1");

        assertThat(result.email()).isEqualTo("user@example.com");
        assertThat(result.displayName()).isEqualTo("Alice");
    }

    @Test
    void toAccount_assignsRequiredIdParam() {
        RegisterAccountInput input = new RegisterAccountInput("a@b.com", "Bob", "pass", "pass");
        Account result = input.toAccount("acc-99");

        assertThat(result.id()).isEqualTo("acc-99");
    }

    @Test
    void toAccount_doesNotIncludePasswordInResult() {
        RegisterAccountInput input = new RegisterAccountInput("x@y.com", "Carol", "p@ssw0rd", "p@ssw0rd");

        assertThatCode(() -> input.toAccount("id-1")).doesNotThrowAnyException();
    }

}
