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
 * Case 10 — List of list of mapped input objects with element nullability mismatch.
 *
 * schema:
 *   type Grid  { cells: [[Cell]]!  }   outer non-null, inner nullable, elements nullable
 *   input GridInput @glMapsTo(type: "Grid")
 *            { cells: [[CellInput!]]! } outer non-null, inner nullable, elements non-null
 *
 * toGrid():   cells → stream over rows; null inner list stays null; else stream e1.toCell()
 * fromGrid(): element nullability mismatch (Cell? ≠ CellInput!) → cells is a required param
 */
class MappingCase10Test {

    // -------------------------------------------------------------------------
    // CellInput — toCell / fromCell
    // -------------------------------------------------------------------------

    @Test
    void toCell_mapsValueDirectly() {
        CellInput input = new CellInput("hello");
        Cell result = input.toCell();

        assertThat(result.getValue()).isEqualTo("hello");
    }

    @Test
    void fromCell_mapsValueDirectly() {
        Cell cell = new Cell("world");
        CellInput result = CellInput.fromCell(cell);

        assertThat(result.getValue()).isEqualTo("world");
    }

    @Test
    void cell_roundTrip() {
        CellInput original = new CellInput("data");
        CellInput roundTrip = CellInput.fromCell(original.toCell());

        assertThat(roundTrip.getValue()).isEqualTo(original.getValue());
    }

    // -------------------------------------------------------------------------
    // GridInput — toGrid
    // -------------------------------------------------------------------------

    @Test
    void toGrid_mapsNonNullInnerRows() {
        List<List<CellInput>> rows = Arrays.asList(
                Arrays.asList(new CellInput("a"), new CellInput("b")),
                Arrays.asList(new CellInput("c"))
        );
        GridInput input = new GridInput(rows);
        Grid result = input.toGrid();

        assertThat(result.getCells()).hasSize(2);
        assertThat(result.getCells().get(0)).hasSize(2);
        assertThat(result.getCells().get(0).get(0).getValue()).isEqualTo("a");
        assertThat(result.getCells().get(0).get(1).getValue()).isEqualTo("b");
        assertThat(result.getCells().get(1).get(0).getValue()).isEqualTo("c");
    }

    @Test
    void toGrid_preservesNullInnerRow() {
        // Inner list is nullable — a null row should survive as null in the result
        List<List<CellInput>> rows = Arrays.asList(
                null,
                Arrays.asList(new CellInput("x"))
        );
        GridInput input = new GridInput(rows);
        Grid result = input.toGrid();

        assertThat(result.getCells()).hasSize(2);
        assertThat(result.getCells().get(0)).isNull();
        assertThat(result.getCells().get(1).get(0).getValue()).isEqualTo("x");
    }

    @Test
    void toGrid_withEmptyOuterListDoesNotThrow() {
        GridInput input = new GridInput(Collections.emptyList());

        assertThatCode(() -> input.toGrid()).doesNotThrowAnyException();
    }

    @Test
    void toGrid_withEmptyInnerListProducesEmptyRow() {
        GridInput input = new GridInput(Arrays.asList(Collections.emptyList()));
        Grid result = input.toGrid();

        assertThat(result.getCells()).hasSize(1);
        assertThat(result.getCells().get(0)).isEmpty();
    }

    // -------------------------------------------------------------------------
    // GridInput — fromGrid
    // cells is a required param because Cell? elements can't feed CellInput! slots.
    // -------------------------------------------------------------------------

    @Test
    void fromGrid_usesCellsParam() {
        Grid grid = new Grid(Arrays.asList(
                Arrays.asList(new Cell("p"), new Cell("q"))
        ));
        List<List<CellInput>> cellsParam = Arrays.asList(
                Arrays.asList(new CellInput("p"), new CellInput("q"))
        );

        GridInput result = GridInput.fromGrid(grid, cellsParam);

        assertThat(result.getCells()).isSameAs(cellsParam);
    }

    @Test
    void fromGrid_withNullInnerRowInParamDoesNotThrow() {
        Grid grid = new Grid(Arrays.asList(
                Arrays.asList(new Cell("z"))
        ));
        List<List<CellInput>> cellsParam = Arrays.asList(
                null,
                Arrays.asList(new CellInput("z"))
        );

        assertThatCode(() -> GridInput.fromGrid(grid, cellsParam)).doesNotThrowAnyException();
    }

    @Test
    void fromGrid_thenToGrid_roundTrip() {
        Grid original = new Grid(Arrays.asList(
                Arrays.asList(new Cell("v1"), new Cell("v2")),
                Arrays.asList(new Cell("v3"))
        ));
        List<List<CellInput>> cellsParam = Arrays.asList(
                Arrays.asList(new CellInput("v1"), new CellInput("v2")),
                Arrays.asList(new CellInput("v3"))
        );
        GridInput input = GridInput.fromGrid(original, cellsParam);
        Grid result = input.toGrid();

        assertThat(result.getCells()).hasSize(2);
        assertThat(result.getCells().get(0).get(0).getValue()).isEqualTo("v1");
        assertThat(result.getCells().get(0).get(1).getValue()).isEqualTo("v2");
        assertThat(result.getCells().get(1).get(0).getValue()).isEqualTo("v3");
    }
}
