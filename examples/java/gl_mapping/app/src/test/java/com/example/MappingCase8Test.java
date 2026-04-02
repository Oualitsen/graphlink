package com.example;

import com.example.generated.enums.Status;
import com.example.generated.inputs.EnumListInputA;
import com.example.generated.inputs.EnumListInputB;
import com.example.generated.inputs.EnumListInputC;
import com.example.generated.inputs.EnumListInputD;
import com.example.generated.types.EnumListA;
import com.example.generated.types.EnumListB;
import com.example.generated.types.EnumListC;
import com.example.generated.types.EnumListD;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 8 — Enum list nullability combos (Status enum).
 *
 *   A: [Status!]! input → [Status!]! target  — direct copy, no params
 *   B: [Status!]  input → [Status!]! target  — nullable source, defaultStatuses param
 *   C: [Status!]! input → [Status!]  target  — non-null source → nullable target
 *   D: [Status!]  input → [Status!]  target  — both nullable
 */
class MappingCase8Test {

    // -------------------------------------------------------------------------
    // Case A: [Status!]! → [Status!]!
    // -------------------------------------------------------------------------

    @Test
    void caseA_toEnumListA_copiesStatusesDirectly() {
        EnumListInputA input = new EnumListInputA(Arrays.asList(Status.ACTIVE, Status.PENDING));
        EnumListA result = input.toEnumListA();

        assertThat(result.getStatuses()).containsExactly(Status.ACTIVE, Status.PENDING);
    }

    @Test
    void caseA_fromEnumListA_copiesStatusesDirectly() {
        EnumListA source = new EnumListA(Arrays.asList(Status.INACTIVE));
        EnumListInputA result = EnumListInputA.fromEnumListA(source);

        assertThat(result.getStatuses()).containsExactly(Status.INACTIVE);
    }

    @Test
    void caseA_roundTrip() {
        EnumListInputA original = new EnumListInputA(Arrays.asList(Status.ACTIVE, Status.INACTIVE, Status.PENDING));
        EnumListInputA roundTrip = EnumListInputA.fromEnumListA(original.toEnumListA());

        assertThat(roundTrip.getStatuses()).isEqualTo(original.getStatuses());
    }

    // -------------------------------------------------------------------------
    // Case B: [Status!] (nullable) → [Status!]! (non-null) — default param
    // -------------------------------------------------------------------------

    @Test
    void caseB_toEnumListB_usesActualStatusesWhenPresent() {
        EnumListInputB input = new EnumListInputB(Arrays.asList(Status.ACTIVE));
        EnumListB result = input.toEnumListB(Arrays.asList(Status.INACTIVE));

        assertThat(result.getStatuses()).containsExactly(Status.ACTIVE);
    }

    @Test
    void caseB_toEnumListB_fallsBackToDefaultWhenStatusesNull() {
        EnumListInputB input = new EnumListInputB(null);
        EnumListB result = input.toEnumListB(Arrays.asList(Status.PENDING));

        assertThat(result.getStatuses()).containsExactly(Status.PENDING);
    }

    @Test
    void caseB_fromEnumListB_copiesStatusesDirectly() {
        EnumListB source = new EnumListB(Arrays.asList(Status.ACTIVE, Status.PENDING));
        EnumListInputB result = EnumListInputB.fromEnumListB(source);

        assertThat(result.getStatuses()).containsExactly(Status.ACTIVE, Status.PENDING);
    }

    // -------------------------------------------------------------------------
    // Case C: [Status!]! → [Status!] (nullable target)
    // -------------------------------------------------------------------------

    @Test
    void caseC_toEnumListC_copiesStatusesDirectly() {
        EnumListInputC input = new EnumListInputC(Arrays.asList(Status.INACTIVE, Status.ACTIVE));
        EnumListC result = input.toEnumListC();

        assertThat(result.getStatuses()).containsExactly(Status.INACTIVE, Status.ACTIVE);
    }

    @Test
    void caseC_fromEnumListC_copiesNullableStatusesWhenPresent() {
        EnumListC source = new EnumListC(Arrays.asList(Status.PENDING));
        EnumListInputC result = EnumListInputC.fromEnumListC(source, Arrays.asList(Status.INACTIVE));

        assertThat(result.getStatuses()).containsExactly(Status.PENDING);
    }

    @Test
    void caseC_fromEnumListC_usesDefaultWhenTargetStatusesNull() {
        // target statuses is nullable → fromEnumListC needs a defaultStatuses param
        EnumListC source = new EnumListC(null);
        EnumListInputC result = EnumListInputC.fromEnumListC(source, Arrays.asList(Status.INACTIVE));

        assertThat(result.getStatuses()).containsExactly(Status.INACTIVE);
    }

    // -------------------------------------------------------------------------
    // Case D: [Status!] (nullable) → [Status!] (nullable)
    // -------------------------------------------------------------------------

    @Test
    void caseD_toEnumListD_withNullStatusesDoesNotThrow() {
        EnumListInputD input = new EnumListInputD(null);

        assertThatCode(() -> input.toEnumListD()).doesNotThrowAnyException();
    }

    @Test
    void caseD_toEnumListD_copiesStatusesWhenPresent() {
        EnumListInputD input = new EnumListInputD(Arrays.asList(Status.ACTIVE));
        EnumListD result = input.toEnumListD();

        assertThat(result.getStatuses()).containsExactly(Status.ACTIVE);
    }

    @Test
    void caseD_fromEnumListD_copiesNullableStatuses() {
        EnumListD source = new EnumListD(Arrays.asList(Status.INACTIVE));
        EnumListInputD result = EnumListInputD.fromEnumListD(source);

        assertThat(result.getStatuses()).containsExactly(Status.INACTIVE);
    }
}
