package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestFragmentThatSpreadsAnotherFragment(t *testing.T) {
	u := must(newClient(t).Queries.FragNested(ctx(t), "user-1")).GetUser
	expectEqual(t, u.Id, "user-1", "id")
	expectEqual(t, u.Name, "Alice Smith", "name")
	expectEqual(t, u.Status, gl.UserStatusActive, "status")
}

func TestFragmentReusedByTwoOperations(t *testing.T) {
	c := newClient(t)
	all := must(c.Queries.FragReuseA(ctx(t))).ListUsers
	ids := map[string]bool{}
	for _, u := range all {
		ids[u.Id] = true
	}
	expectEqual(t, ids["user-1"] && ids["user-2"], true, "both users")
	one := must(c.Queries.FragReuseB(ctx(t), "user-2")).GetUser
	expectEqual(t, one.Id, "user-2", "id")
	expectEqual(t, one.Name, "Bob Jones", "name")
	expectEqual(t, one.Email != "", true, "email")
}

func TestFragmentOnInterfaceNextToInlineFragment(t *testing.T) {
	feed := must(newClient(t).Queries.FragOnInterface(ctx(t))).Feed
	if len(feed) == 0 {
		t.Fatal("empty feed")
	}
	for _, e := range feed {
		if e.GetId() == "" || e.GetCreatedBy() == "" {
			t.Fatalf("incomplete entity %#v", e)
		}
	}
}

func TestSeveralRootFieldsSharingOneFragment(t *testing.T) {
	r := must(newClient(t).Queries.MultiRoot(ctx(t)))
	expectEqual(t, r.First.Name, "Alice Smith", "first")
	expectEqual(t, r.Second.Name, "Bob Jones", "second")
	expectEqual(t, len(r.All) >= 2, true, "all")
}

func TestVariableDefaultsApplyWhenNotGiven(t *testing.T) {
	expectEqual(t, len(must(newClient(t).Queries.VarsDefaults(ctx(t))).SearchUsers), 1, "length")
}

func TestExplicitValueReplacesVariableDefault(t *testing.T) {
	name, limit := "Alice", 5
	r := must(newClient(t).Queries.VarsDefaults(ctx(t), gl.VarsDefaultsOptions{Name: &name, Limit: &limit})).SearchUsers
	expectEqual(t, len(r), 1, "length")
	expectEqual(t, r[0].Id, "user-1", "id")
}

func TestListNestedListAndEnumVariables(t *testing.T) {
	r := must(newClient(t).Queries.VarsLists(ctx(t), []int{1, 2}, []gl.Spelling{gl.SpellingXY}, gl.VarsListsOptions{
		B: []*int{intp(1), nil},
		C: [][]int{{1}, {2, 3}},
		F: []*gl.Spelling{nil, sp(gl.SpellingV1)},
	})).EchoArgs
	expectDeep(t, r.A, []int{1, 2}, "a")
	expectDeep(t, r.B, []*int{intp(1), nil}, "b")
	expectDeep(t, r.C, [][]int{{1}, {2, 3}}, "c")
	expectDeep(t, r.E, []gl.Spelling{gl.SpellingXY}, "e")
	expectDeep(t, r.F, []*gl.Spelling{nil, sp(gl.SpellingV1)}, "f")
}

func TestNullableEnumVariable(t *testing.T) {
	one := gl.OnlyOneOnly
	expectEqual(t, must(newClient(t).Queries.VarsEnum(ctx(t), gl.VarsEnumOptions{One: &one})).EchoArgs.One, gl.OnlyOneOnly, "one")
}

func TestInputObjectVariable(t *testing.T) {
	n, label := 4, "x"
	r := must(newClient(t).Queries.VarsInput(ctx(t), gl.InnerInput{N: &n, Label: &label})).EchoInner
	expectEqual(t, *r.N, 4, "n")
	expectEqual(t, *r.Label, "x", "label")
}

func TestNullableVersusNonNullVariables(t *testing.T) {
	c := newClient(t)
	d := "$d"
	given := must(c.Queries.VarsNullable(ctx(t), "q", gl.VarsNullableOptions{Dollar: &d})).EchoNastyArgs
	expectEqual(t, *given.Dollar, "$d", "dollar")
	left := must(c.Queries.VarsNullable(ctx(t), "q")).EchoNastyArgs
	if left.Dollar != nil {
		t.Fatal("dollar should be nil")
	}
	expectEqual(t, *left.Quote, "q", "quote")
}

func TestIncludeAndSkipWithVariables(t *testing.T) {
	c := newClient(t)
	both := must(c.Queries.ConditionalVars(ctx(t), true, false)).GetUser
	expectEqual(t, *both.Name, "Alice Smith", "name")
	expectEqual(t, *both.Email, "alice@test.com", "email")
	neither := must(c.Queries.ConditionalVars(ctx(t), false, true)).GetUser
	expectEqual(t, neither.Id, "user-1", "id")
	if neither.Name != nil || neither.Email != nil {
		t.Fatal("skipped fields should be nil")
	}
}

func TestIncludeAndSkipWithLiterals(t *testing.T) {
	u := must(newClient(t).Queries.ConditionalLiterals(ctx(t))).GetUser
	expectEqual(t, *u.Name, "Alice Smith", "name")
	expectEqual(t, *u.Status, gl.UserStatusActive, "status")
	if u.Email != nil || u.Priority != nil {
		t.Fatal("excluded fields should be nil")
	}
}

func TestAliases(t *testing.T) {
	c := newClient(t)
	r := must(c.Queries.AliasesSameField(ctx(t)))
	expectEqual(t, r.A.Id, "user-1", "a")
	expectEqual(t, r.B.Id, "user-2", "b")
	k := must(c.Queries.AliasKeywords(ctx(t))).Class
	expectEqual(t, k.Default, "Alice Smith", "default")
	expectEqual(t, k.Import, "user-1", "import")
	expectEqual(t, must(c.Queries.AliasEqualsOtherField(ctx(t))).GetUser.Name, "alice@test.com", "name")
}

func TestOperationNamesThatCollide(t *testing.T) {
	c := newClient(t)
	expectEqual(t, must(c.Queries.User(ctx(t))).GetUser.Id, "user-1", "type name")
	expectEqual(t, must(c.Queries.Photo2(ctx(t))).Photo.Id, "ph1", "type name 2")
	expectEqual(t, len(must(c.Queries.Return(ctx(t))).ListUsers) > 0, true, "keyword")
	expectEqual(t, must(c.Queries.Shelf(ctx(t))).Shelf.Id, "s1", "auto-generated name")
	expectEqual(t, must(c.Queries.GetUserResponse(ctx(t))).GetUser.Id, "user-1", "response name")
}

func TestFieldArgumentsOfEveryShape(t *testing.T) {
	c := newClient(t)
	expectDeep(t, must(c.Queries.ShelfItems(ctx(t))).Shelf.Items,
		[]string{"tags=[a, b]", "kind=x__y", "filter={n=3, label=L}", "limit=5"}, "literals")
	n, label, limit, kind := 1, "f", 7, gl.SpellingV1
	r := must(c.Queries.ShelfItemsVars(ctx(t), gl.ShelfItemsVarsOptions{
		Tags: []string{"t"}, Kind: &kind, Filter: &gl.InnerInput{N: &n, Label: &label}, Limit: &limit,
	})).Shelf.Items
	expectEqual(t, r[0], "tags=[t]", "tags")
	expectEqual(t, r[1], "kind=v1", "kind")
	expectEqual(t, r[3], "limit=7", "limit")
	items := must(c.Queries.ShelfItemsDefaults(ctx(t))).Shelf.Items
	expectEqual(t, items[len(items)-1], "limit=2", "server default")
}

func TestLiteralArgumentsOfEveryKind(t *testing.T) {
	c := newClient(t)
	l := must(c.Queries.LiteralLists(ctx(t))).EchoArgs
	expectDeep(t, l.A, []int{1, 2, 3}, "a")
	expectDeep(t, l.B, []*int{intp(1), nil}, "b")
	expectDeep(t, l.C, [][]int{{1}, {2, 3}}, "c")
	expectDeep(t, l.E, []gl.Spelling{gl.SpellingA, gl.SpellingXY}, "e")
	expectDeep(t, l.F, []*gl.Spelling{nil, sp(gl.SpellingV1)}, "f")
	expectDeep(t, l.G, []gl.Spelling{gl.SpellingSnakeCase2}, "g")
	expectEqual(t, l.One, gl.OnlyOneOnly, "one")

	i := must(c.Queries.LiteralInput(ctx(t))).EchoInput
	expectDeep(t, i.A, []int{4}, "input a")
	expectDeep(t, i.B, []*int{nil, intp(5)}, "input b")
	expectDeep(t, i.C, [][]int{{6}}, "input c")

	s := must(c.Queries.LiteralScalars(ctx(t))).EchoEverything
	expectEqual(t, *s.I, 5, "i")
	expectEqual(t, *s.Neg, -3, "neg")
	expectEqual(t, *s.F, 2.5, "f")
	expectEqual(t, *s.Exp, 100.0, "exp")
	expectEqual(t, *s.B, false, "b")
	expectEqual(t, *s.Bf, true, "bf")
	expectEqual(t, *s.S, "lit", "s")
	expectEqual(t, *s.E, gl.SpellingV1, "e")
	expectEqual(t, *s.Inner.Label, "L", "inner")
	if s.Nothing != nil || s.EmptyObj.N != nil {
		t.Fatal("null literals should stay nil")
	}

	one := gl.OnlyOneOnly
	m := must(c.Queries.LiteralsMixed(ctx(t), []int{8}, gl.LiteralsMixedOptions{One: &one})).EchoArgs
	expectDeep(t, m.A, []int{8}, "mixed a")
	expectDeep(t, m.E, []gl.Spelling{gl.SpellingA, gl.SpellingB2}, "mixed e")
}
