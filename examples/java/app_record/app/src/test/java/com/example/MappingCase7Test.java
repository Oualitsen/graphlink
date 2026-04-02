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

import static org.assertj.core.api.Assertions.*;

/**
 * Case 7 — Scalar list nullability combos (String).
 * A: [String!]! → [String!]!  direct copy, no params
 * B: [String!]  → [String!]!  nullable source → defaultTags param
 * C: [String!]! → [String!]   non-null source → nullable target, defaultTags in fromXxx
 * D: [String!]  → [String!]   both nullable, direct copy
 */
class MappingCase7Test {

    // Case A
    @Test
    void caseA_toScalarListA_copiesTagsDirectly() {
        assertThat(new ScalarListInputA(Arrays.asList("foo", "bar")).toScalarListA().tags())
                .containsExactly("foo", "bar");
    }

    @Test
    void caseA_fromScalarListA_copiesTagsDirectly() {
        assertThat(ScalarListInputA.fromScalarListA(new ScalarListA(Arrays.asList("x", "y"))).tags())
                .containsExactly("x", "y");
    }

    @Test
    void caseA_roundTrip() {
        ScalarListInputA original = new ScalarListInputA(Arrays.asList("a", "b", "c"));
        assertThat(ScalarListInputA.fromScalarListA(original.toScalarListA()).tags())
                .isEqualTo(original.tags());
    }

    // Case B — nullable source needs defaultTags in toXxx
    @Test
    void caseB_toScalarListB_usesActualTagsWhenPresent() {
        assertThat(new ScalarListInputB(Arrays.asList("hello")).toScalarListB(Arrays.asList("default")).tags())
                .containsExactly("hello");
    }

    @Test
    void caseB_toScalarListB_fallsBackToDefaultWhenNull() {
        assertThat(new ScalarListInputB(null).toScalarListB(Arrays.asList("fallback")).tags())
                .containsExactly("fallback");
    }

    @Test
    void caseB_fromScalarListB_copiesTagsDirectly() {
        assertThat(ScalarListInputB.fromScalarListB(new ScalarListB(Arrays.asList("p", "q"))).tags())
                .containsExactly("p", "q");
    }

    // Case C — non-null source → nullable target; fromXxx needs defaultTags
    @Test
    void caseC_toScalarListC_copiesTagsDirectly() {
        assertThat(new ScalarListInputC(Arrays.asList("m", "n")).toScalarListC().tags())
                .containsExactly("m", "n");
    }

    @Test
    void caseC_fromScalarListC_copiesTagsWhenPresent() {
        assertThat(ScalarListInputC.fromScalarListC(new ScalarListC(Arrays.asList("r", "s")), Arrays.asList("default")).tags())
                .containsExactly("r", "s");
    }

    @Test
    void caseC_fromScalarListC_usesDefaultWhenTargetTagsNull() {
        assertThat(ScalarListInputC.fromScalarListC(new ScalarListC(null), Arrays.asList("fallback")).tags())
                .containsExactly("fallback");
    }

    // Case D — both nullable
    @Test
    void caseD_toScalarListD_copiesTagsWhenPresent() {
        assertThat(new ScalarListInputD(Arrays.asList("u", "v")).toScalarListD().tags())
                .containsExactly("u", "v");
    }

    @Test
    void caseD_toScalarListD_withNullTagsDoesNotThrow() {
        assertThatCode(() -> new ScalarListInputD(null).toScalarListD()).doesNotThrowAnyException();
    }

    @Test
    void caseD_fromScalarListD_copiesNullableTags() {
        assertThat(ScalarListInputD.fromScalarListD(new ScalarListD(Arrays.asList("w"))).tags())
                .containsExactly("w");
    }
}
