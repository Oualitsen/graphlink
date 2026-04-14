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

    @Test
    void fromCell_mapsValueDirectly() {
        assertThat(CellInput.fromCell(new Cell("world")).value()).isEqualTo("world");
    }

    @Test
    void cell_roundTrip() {
        CellInput original = new CellInput("data");
        assertThat(CellInput.fromCell(original.toCell()).value()).isEqualTo(original.value());
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

    @Test
    void fromGrid_usesCellsParam() {
        Grid grid = new Grid(Arrays.asList(Arrays.asList(new Cell("p"), new Cell("q"))));
        List<List<CellInput>> cellsParam = Arrays.asList(
                Arrays.asList(new CellInput("p"), new CellInput("q")));

        assertThat(GridInput.fromGrid(grid, cellsParam).cells()).isSameAs(cellsParam);
    }

    @Test
    void fromGrid_withNullInnerRowInParamDoesNotThrow() {
        Grid grid = new Grid(Arrays.asList(Arrays.asList(new Cell("z"))));
        List<List<CellInput>> cellsParam = Arrays.asList(null, Arrays.asList(new CellInput("z")));

        assertThatCode(() -> GridInput.fromGrid(grid, cellsParam)).doesNotThrowAnyException();
    }

    @Test
    void fromGrid_thenToGrid_roundTrip() {
        Grid original = new Grid(Arrays.asList(
                Arrays.asList(new Cell("v1"), new Cell("v2")),
                Arrays.asList(new Cell("v3"))));
        List<List<CellInput>> cellsParam = Arrays.asList(
                Arrays.asList(new CellInput("v1"), new CellInput("v2")),
                Arrays.asList(new CellInput("v3")));

        Grid result = GridInput.fromGrid(original, cellsParam).toGrid();

        assertThat(result.cells().get(0).get(0).value()).isEqualTo("v1");
        assertThat(result.cells().get(0).get(1).value()).isEqualTo("v2");
        assertThat(result.cells().get(1).get(0).value()).isEqualTo("v3");
    }
}
