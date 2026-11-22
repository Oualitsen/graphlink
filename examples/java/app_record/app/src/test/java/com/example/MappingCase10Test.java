package com.example;

import com.example.generated.inputs.CellInput;
import com.example.generated.inputs.GridInput;
import com.example.generated.types.Cell;
import com.example.generated.types.Grid;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 10 — List of list with element nullability mismatch.
 * Grid: [[Cell]]! — outer non-null, inner nullable, elements nullable.
 * GridInput: [[CellInput!]]! — elements non-null → cells is a required param in fromGrid().
 */
class MappingCase10Test {

    // CellInput — toCell / fromCell

    @Test
    void toCell_mapsValueDirectly() {
        assertThat(new CellInput("hello").toCell().value()).isEqualTo("hello");
    }

    // GridInput — toGrid

    @Test
    void toGrid_mapsNonNullInnerRows() {
        GridInput input = new GridInput(Arrays.asList(
                Arrays.asList(new CellInput("a"), new CellInput("b")),
                Arrays.asList(new CellInput("c"))));

        Grid result = input.toGrid();

        assertThat(result.cells()).hasSize(2);
        assertThat(result.cells().get(0).get(0).value()).isEqualTo("a");
        assertThat(result.cells().get(0).get(1).value()).isEqualTo("b");
        assertThat(result.cells().get(1).get(0).value()).isEqualTo("c");
    }

    @Test
    void toGrid_preservesNullInnerRow() {
        GridInput input = new GridInput(Arrays.asList(
                null,
                Arrays.asList(new CellInput("x"))));

        Grid result = input.toGrid();

        assertThat(result.cells()).hasSize(2);
        assertThat(result.cells().get(0)).isNull();
        assertThat(result.cells().get(1).get(0).value()).isEqualTo("x");
    }

    @Test
    void toGrid_withEmptyOuterListDoesNotThrow() {
        assertThatCode(() -> new GridInput(Collections.emptyList()).toGrid()).doesNotThrowAnyException();
    }

    @Test
    void toGrid_withEmptyInnerListProducesEmptyRow() {
        Grid result = new GridInput(Arrays.asList(Collections.emptyList())).toGrid();

        assertThat(result.cells()).hasSize(1);
        assertThat(result.cells().get(0)).isEmpty();
    }

    // GridInput — fromGrid (cells is a required param)

}
