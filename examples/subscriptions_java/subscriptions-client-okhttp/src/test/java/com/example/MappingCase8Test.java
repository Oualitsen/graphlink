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

import static org.assertj.core.api.Assertions.*;

/**
 * Case 8 — Enum list nullability combos (Status).
 * A: [Status!]! → [Status!]!  direct copy
 * B: [Status!]  → [Status!]!  nullable source → defaultStatuses param
 * C: [Status!]! → [Status!]   non-null source → nullable target, defaultStatuses in fromXxx
 * D: [Status!]  → [Status!]   both nullable, direct copy
 */
class MappingCase8Test {

    // Case A
    @Test
    void caseA_toEnumListA_copiesStatusesDirectly() {
        assertThat(new EnumListInputA(Arrays.asList(Status.ACTIVE, Status.PENDING)).toEnumListA().statuses())
                .containsExactly(Status.ACTIVE, Status.PENDING);
    }

    @Test
    void caseA_fromEnumListA_copiesStatusesDirectly() {
        assertThat(EnumListInputA.fromEnumListA(new EnumListA(Arrays.asList(Status.INACTIVE))).statuses())
                .containsExactly(Status.INACTIVE);
    }

    @Test
    void caseA_roundTrip() {
        EnumListInputA original = new EnumListInputA(Arrays.asList(Status.ACTIVE, Status.INACTIVE, Status.PENDING));
        assertThat(EnumListInputA.fromEnumListA(original.toEnumListA()).statuses())
                .isEqualTo(original.statuses());
    }

    // Case B — nullable source needs defaultStatuses in toXxx
    @Test
    void caseB_toEnumListB_usesActualStatusesWhenPresent() {
        assertThat(new EnumListInputB(Arrays.asList(Status.ACTIVE)).toEnumListB(Arrays.asList(Status.INACTIVE)).statuses())
                .containsExactly(Status.ACTIVE);
    }

    @Test
    void caseB_toEnumListB_fallsBackToDefaultWhenNull() {
        assertThat(new EnumListInputB(null).toEnumListB(Arrays.asList(Status.PENDING)).statuses())
                .containsExactly(Status.PENDING);
    }

    @Test
    void caseB_fromEnumListB_copiesStatusesDirectly() {
        assertThat(EnumListInputB.fromEnumListB(new EnumListB(Arrays.asList(Status.ACTIVE, Status.PENDING))).statuses())
                .containsExactly(Status.ACTIVE, Status.PENDING);
    }

    // Case C — non-null source → nullable target; fromXxx needs defaultStatuses
    @Test
    void caseC_toEnumListC_copiesStatusesDirectly() {
        assertThat(new EnumListInputC(Arrays.asList(Status.INACTIVE, Status.ACTIVE)).toEnumListC().statuses())
                .containsExactly(Status.INACTIVE, Status.ACTIVE);
    }

    @Test
    void caseC_fromEnumListC_copiesStatusesWhenPresent() {
        assertThat(EnumListInputC.fromEnumListC(new EnumListC(Arrays.asList(Status.PENDING)), Arrays.asList(Status.INACTIVE)).statuses())
                .containsExactly(Status.PENDING);
    }

    @Test
    void caseC_fromEnumListC_usesDefaultWhenTargetStatusesNull() {
        assertThat(EnumListInputC.fromEnumListC(new EnumListC(null), Arrays.asList(Status.INACTIVE)).statuses())
                .containsExactly(Status.INACTIVE);
    }

    // Case D — both nullable
    @Test
    void caseD_toEnumListD_withNullStatusesDoesNotThrow() {
        assertThatCode(() -> new EnumListInputD(null).toEnumListD()).doesNotThrowAnyException();
    }

    @Test
    void caseD_toEnumListD_copiesStatusesWhenPresent() {
        assertThat(new EnumListInputD(Arrays.asList(Status.ACTIVE)).toEnumListD().statuses())
                .containsExactly(Status.ACTIVE);
    }

    @Test
    void caseD_fromEnumListD_copiesNullableStatuses() {
        assertThat(EnumListInputD.fromEnumListD(new EnumListD(Arrays.asList(Status.INACTIVE))).statuses())
                .containsExactly(Status.INACTIVE);
    }
}
