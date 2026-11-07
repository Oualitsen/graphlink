package tests

import (
	"reflect"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

var knownSpellings = []gl.Spelling{
	gl.SpellingA, gl.SpellingB2, gl.SpellingXY, gl.SpellingHttp2Ok, gl.SpellingV1, gl.SpellingSnakeCase2,
}

func intp(v int) *int { return &v }

func sp(v gl.Spelling) *gl.Spelling { return &v }

func expectDeep(t *testing.T, got, want any, what string) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%s: got %#v, want %#v", what, got, want)
	}
}

func shapes(t *testing.T, mode string) gl.ListShapes {
	return must(newClient(t).Queries.ListShapes(ctx(t), mode)).ListShapes
}

func TestListShapesScalarsWithNulls(t *testing.T) {
	s := shapes(t, "full")
	expectDeep(t, s.A, []int{1, 2, 3}, "a")
	expectDeep(t, s.B, []int{1, 2, 3}, "b")
	expectDeep(t, s.C, []*int{intp(1), nil, intp(3)}, "c")
	expectDeep(t, s.D, []*int{nil}, "d")
}

func TestListShapesNestedLists(t *testing.T) {
	s := shapes(t, "full")
	expectDeep(t, s.E, [][]int{{1, 2}, {3}}, "e")
	expectDeep(t, s.F, [][]*int{{intp(1), nil}, nil}, "f")
}

func TestListShapesEnumsWithNulls(t *testing.T) {
	expectDeep(t, shapes(t, "full").G, []*gl.Spelling{sp(gl.SpellingA), nil, sp(gl.SpellingB2)}, "g")
}

func TestListShapesObjectsUnionsAndInterfaces(t *testing.T) {
	s := shapes(t, "full")
	expectEqual(t, len(s.H), 2, "h length")
	expectEqual(t, s.H[0].Width, 640, "h[0].width")
	if s.H[1] != nil {
		t.Fatal("h[1] should be nil")
	}
	expectKinds(t, kinds(s.I), "Photo", "nil", "Video")
	expectKinds(t, kinds(s.J), "Comment", "nil")
}

func TestListShapesEmptyListsStayEmpty(t *testing.T) {
	s := shapes(t, "empty")
	for name, l := range map[string]int{"b": len(s.B), "d": len(s.D), "f": len(s.F), "e": len(s.E)} {
		expectEqual(t, l, 0, name)
	}
	if s.B == nil || s.D == nil || s.F == nil {
		t.Fatal("an empty list must not decode as nil")
	}
}

func TestListShapesNullListsStayNull(t *testing.T) {
	s := shapes(t, "null")
	if s.B != nil || s.D != nil || s.F != nil {
		t.Fatal("null lists must decode as nil")
	}
	expectEqual(t, len(s.A)+len(s.G)+len(s.I), 0, "required lists are empty")
}

func TestListArgumentsRoundTrip(t *testing.T) {
	r := must(newClient(t).Queries.EchoArgs(ctx(t), []int{1, 2}, []gl.Spelling{gl.SpellingXY, gl.SpellingHttp2Ok}, gl.EchoArgsOptions{
		B: []*int{intp(1), nil},
		C: [][]int{{1}, {}, {2, 3}},
		F: []*gl.Spelling{nil, sp(gl.SpellingV1)},
	})).EchoArgs
	expectDeep(t, r.A, []int{1, 2}, "a")
	expectDeep(t, r.B, []*int{intp(1), nil}, "b")
	expectDeep(t, r.C, [][]int{{1}, {}, {2, 3}}, "c")
	expectDeep(t, r.E, []gl.Spelling{gl.SpellingXY, gl.SpellingHttp2Ok}, "e")
	expectDeep(t, r.F, []*gl.Spelling{nil, sp(gl.SpellingV1)}, "f")
}

func TestListArgumentsOmittedAreNullAndDefaultsApply(t *testing.T) {
	r := must(newClient(t).Queries.EchoArgs(ctx(t), []int{}, []gl.Spelling{})).EchoArgs
	if r.B != nil || r.C != nil || r.F != nil {
		t.Fatal("omitted lists must come back nil")
	}
	expectDeep(t, r.G, []gl.Spelling{gl.SpellingA, gl.SpellingB2}, "g")
	expectEqual(t, r.One, gl.OnlyOneOnly, "one")
}

func TestListArgumentsExplicitlyEmptyDefaultBearingListIsKept(t *testing.T) {
	r := must(newClient(t).Queries.EchoArgs(ctx(t), []int{}, []gl.Spelling{}, gl.EchoArgsOptions{G: []gl.Spelling{}})).EchoArgs
	expectEqual(t, len(r.G), 0, "g")
}

func TestListInputFieldsRoundTrip(t *testing.T) {
	input := gl.NewListsInput()
	input.A = []int{3, 4}
	input.B = []*int{nil, intp(5)}
	input.C = [][]int{{1, 2}, {}}
	input.E = []gl.Spelling{gl.SpellingSnakeCase2}
	input.F = []*gl.Spelling{sp(gl.SpellingA), nil}
	input.G = []gl.Spelling{gl.SpellingV1}
	r := must(newClient(t).Queries.EchoInput(ctx(t), input)).EchoInput
	expectDeep(t, r.A, []int{3, 4}, "a")
	expectDeep(t, r.B, []*int{nil, intp(5)}, "b")
	expectDeep(t, r.C, [][]int{{1, 2}, {}}, "c")
	expectDeep(t, r.E, []gl.Spelling{gl.SpellingSnakeCase2}, "e")
	expectDeep(t, r.F, []*gl.Spelling{sp(gl.SpellingA), nil}, "f")
	expectDeep(t, r.G, []gl.Spelling{gl.SpellingV1}, "g")
}

func TestListInputDefaultsReachTheServer(t *testing.T) {
	input := gl.NewListsInput()
	input.A = []int{}
	input.E = []gl.Spelling{}
	r := must(newClient(t).Queries.EchoInput(ctx(t), input)).EchoInput
	expectDeep(t, r.G, []gl.Spelling{gl.SpellingA, gl.SpellingB2}, "g")
	expectEqual(t, r.One, gl.OnlyOneOnly, "one")
}

func TestLargeListOfScalars(t *testing.T) {
	r := must(newClient(t).Queries.BigInts(ctx(t), 50000)).BigInts
	expectEqual(t, len(r), 50000, "length")
	expectEqual(t, r[49999], 49999, "last")
}

func TestLargeListOfObjects(t *testing.T) {
	r := must(newClient(t).Queries.BigPhotos(ctx(t), 20000)).BigPhotos
	expectEqual(t, len(r), 20000, "length")
	expectEqual(t, r[19999].Id, "p19999", "id")
	expectEqual(t, r[19999].Width, 19999, "width")
}

func TestEnumSpellingsRoundTrip(t *testing.T) {
	r := must(newClient(t).Queries.EchoArgs(ctx(t), []int{}, knownSpellings)).EchoArgs
	expectDeep(t, r.E, knownSpellings, "e")
}

func TestEnumSpellingsWireNames(t *testing.T) {
	want := []string{"A", "B2", "x__y", "http2_ok", "v1", "snake_case_2"}
	for i, v := range knownSpellings {
		expectEqual(t, string(v), want[i], "wire name")
	}
}

func TestEnumUsedOnlyAsArgument(t *testing.T) {
	expectEqual(t, must(newClient(t).Queries.ArgOnly(ctx(t), gl.ArgOnlyP2)).ArgOnly, "P2", "argOnly")
}

func TestEnumUsedOnlyInResponse(t *testing.T) {
	expectEqual(t, must(newClient(t).Queries.RespOnly(ctx(t))).RespOnly, gl.RespOnlyR2, "respOnly")
}

func TestUnknownEnumValueInAField(t *testing.T) {
	p := must(newClient(t).Queries.PhaseProbe(ctx(t))).PhaseProbe
	expectEqual(t, p.Single, gl.PhaseUnknownValue__, "single")
	expectEqual(t, *p.Maybe, gl.PhaseUnknownValue__, "maybe")
}

func TestUnknownEnumValueInListElements(t *testing.T) {
	p := must(newClient(t).Queries.PhaseProbe(ctx(t))).PhaseProbe
	expectDeep(t, p.List, []gl.Phase{gl.PhaseOpen, gl.PhaseUnknownValue__, gl.PhaseClosed}, "list")
	expectEqual(t, len(p.NullableList), 2, "nullable list length")
	expectEqual(t, *p.NullableList[0], gl.PhaseUnknownValue__, "nullable list[0]")
	if p.NullableList[1] != nil {
		t.Fatal("nullable list[1] should be nil")
	}
}

func TestUnknownEnumValueInAUnionMember(t *testing.T) {
	h, ok := must(newClient(t).Queries.PhaseHolder(ctx(t))).PhaseHolder.(gl.Phased)
	if !ok {
		t.Fatal("not a Phased")
	}
	expectEqual(t, h.Phase, gl.PhaseUnknownValue__, "phase")
}
