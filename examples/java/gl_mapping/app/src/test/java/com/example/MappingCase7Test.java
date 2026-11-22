package com.example;

import com.example.generated.inputs.ScalarListInputA;
import com.example.generated.inputs.ScalarListInputB;
import com.example.generated.inputs.ScalarListInputC;
import com.example.generated.inputs.ScalarListInputD;
import com.example.generated.types.ScalarListA;
import com.example.generated.types.ScalarListB;
import com.example.generated.types.ScalarListC;
import com.example.generated.types.ScalarListD;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 7 — Scalar list nullability combos (String).
 *
 *   A: [String!]! input → [String!]! target  — direct copy, no params
 *   B: [String!]  input → [String!]! target  — nullable source → non-null target, defaultTags param
 *   C: [String!]! input → [String!]  target  — non-null source → nullable target, direct copy
 *   D: [String!]  input → [String!]  target  — both nullable, direct copy
 */
class MappingCase7Test {

    // -------------------------------------------------------------------------
    // Case A: [String!]! → [String!]!
    // -------------------------------------------------------------------------

    @Test
    void caseA_toScalarListA_copiesTagsDirectly() {
        ScalarListInputA input = new ScalarListInputA(Arrays.asList("foo", "bar"));
        ScalarListA result = input.toScalarListA();

        assertThat(result.getTags()).containsExactly("foo", "bar");
    }

    // -------------------------------------------------------------------------
    // Case B: [String!] (nullable) → [String!]! (non-null target) — default param
    // -------------------------------------------------------------------------

    @Test
    void caseB_toScalarListB_usesActualTagsWhenPresent() {
        ScalarListInputB input = new ScalarListInputB(Arrays.asList("hello"));
        ScalarListB result = input.toScalarListB(Arrays.asList("default"));

        assertThat(result.getTags()).containsExactly("hello");
    }

    @Test
    void caseB_toScalarListB_fallsBackToDefaultWhenTagsNull() {
        ScalarListInputB input = new ScalarListInputB(null);
        ScalarListB result = input.toScalarListB(Arrays.asList("fallback"));

        assertThat(result.getTags()).containsExactly("fallback");
    }

    // -------------------------------------------------------------------------
    // Case C: [String!]! (non-null) → [String!] (nullable target) — direct copy
    // -------------------------------------------------------------------------

    @Test
    void caseC_toScalarListC_copiesTagsDirectly() {
        ScalarListInputC input = new ScalarListInputC(Arrays.asList("m", "n"));
        ScalarListC result = input.toScalarListC();

        assertThat(result.getTags()).containsExactly("m", "n");
    }

    // -------------------------------------------------------------------------
    // Case D: [String!] (nullable) → [String!] (nullable target) — direct copy
    // -------------------------------------------------------------------------

    @Test
    void caseD_toScalarListD_copiesTagsWhenPresent() {
        ScalarListInputD input = new ScalarListInputD(Arrays.asList("u", "v"));
        ScalarListD result = input.toScalarListD();

        assertThat(result.getTags()).containsExactly("u", "v");
    }

    @Test
    void caseD_toScalarListD_withNullTagsDoesNotThrow() {
        ScalarListInputD input = new ScalarListInputD(null);

        assertThatCode(() -> input.toScalarListD()).doesNotThrowAnyException();
    }

}
