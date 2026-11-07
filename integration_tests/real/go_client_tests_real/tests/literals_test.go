package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func expectNasty(t *testing.T, r gl.NastyEcho) {
	t.Helper()
	expectEqual(t, *r.Dollar, `cost $5 and ${x} and $$`, "dollar")
	expectEqual(t, *r.Quote, `say "hi" it's`, "quote")
	expectEqual(t, *r.Backslash, `C:\dir\file\n`, "backslash")
	expectEqual(t, *r.Newline, "line1\nline2\ttab", "newline")
	expectEqual(t, *r.Percent, `100% {braces} {{x}} %s %d`, "percent")
	expectEqual(t, *r.Comments, `a */ b // c /* d`, "comments")
	expectEqual(t, *r.Triple, `""" ''' `+"```", "triple")
	expectEqual(t, *r.Unicode, "café 中 😀", "unicode")
	expectEqual(t, *r.NonAscii, "é中😀", "nonAscii")
}

func TestStringDefaultsOnOperationArguments(t *testing.T) {
	expectNasty(t, must(newClient(t).Queries.EchoNastyArgs(ctx(t))).EchoNastyArgs)
}

func TestStringDefaultsOnInputFieldsThroughAnInputDefaultingToEmptyObject(t *testing.T) {
	expectNasty(t, must(newClient(t).Queries.EchoNasty(ctx(t))).EchoNasty)
}

func TestExplicitValueReplacesTheStringDefault(t *testing.T) {
	y := "$y"
	r := must(newClient(t).Queries.EchoNastyArgs(ctx(t), gl.EchoNastyArgsOptions{Dollar: &y})).EchoNastyArgs
	expectEqual(t, *r.Dollar, "$y", "dollar")
	expectEqual(t, *r.Quote, `say "hi" it's`, "quote")
}

func TestStringLiteralsWrittenInlineInAnOperation(t *testing.T) {
	r := must(newClient(t).Queries.NastyLiteral(ctx(t))).EchoNastyArgs
	expectEqual(t, *r.Dollar, `cost $5 ${x}`, "dollar")
	expectEqual(t, *r.Quote, `say "hi"`, "quote")
	expectEqual(t, *r.Backslash, `C:\dir`, "backslash")
	expectEqual(t, *r.Newline, "a\nb", "newline")
	expectEqual(t, *r.Unicode, "é😀", "unicode")
	expectEqual(t, *r.Triple, `block "x" `, "triple")
}

func TestDefaultsOfEveryKind(t *testing.T) {
	r := must(newClient(t).Queries.EchoEverything(ctx(t), gl.NewEverythingInput())).EchoEverything
	expectEqual(t, *r.I, 42, "i")
	expectEqual(t, *r.Neg, -7, "neg")
	expectEqual(t, *r.Big, 2147483647, "big")
	expectEqual(t, *r.F, 3.14, "f")
	expectEqual(t, *r.Exp, 1000.0, "exp")
	expectEqual(t, *r.B, true, "b")
	expectEqual(t, *r.Bf, false, "bf")
	expectEqual(t, *r.S, "x", "s")
	expectEqual(t, *r.Id, "abc", "id")
	expectEqual(t, *r.E, gl.SpellingXY, "e")
	expectDeep(t, r.Ints, []int{1, 2, 3}, "ints")
	expectDeep(t, r.Nested, [][]int{{1}, {2, 3}}, "nested")
	expectEqual(t, *r.Inner.N, 5, "inner.n")
	expectEqual(t, *r.Inner.Label, "inner", "inner.label")
	if r.Nothing != nil {
		t.Fatal("nothing should be nil")
	}
	expectEqual(t, len(r.EmptyList), 0, "emptyList")
	expectEqual(t, *r.EmptyObj.N, 1, "emptyObj.n")
	expectEqual(t, *r.EmptyObj.Label, "dflt", "emptyObj.label")
}

func TestArgumentWhoseInputTypeHasItsOwnDefaults(t *testing.T) {
	r := must(newClient(t).Queries.EchoInner(ctx(t))).EchoInner
	expectEqual(t, *r.N, 9, "n")
	expectEqual(t, *r.Label, "dflt", "label")
	expectDeep(t, r.Tags, []string{"a"}, "tags")
}

func TestRecursiveTreeInput(t *testing.T) {
	tree := gl.Tree{Value: 1, Children: []gl.Tree{{Value: 2, Children: []gl.Tree{{Value: 4}}}, {Value: 3}}}
	r := must(newClient(t).Queries.TreeStats(ctx(t), tree)).TreeStats
	expectDeep(t, r.Flat, []int{1, 2, 4, 3}, "flat")
	expectEqual(t, r.Depth, 3, "depth")
}

func TestMutuallyRecursiveInputs(t *testing.T) {
	ping := gl.Ping{N: 1, Pong: &gl.Pong{N: 2, Ping: &gl.Ping{N: 3}}}
	expectEqual(t, must(newClient(t).Queries.PingLength(ctx(t), ping)).PingLength, 3, "length")
}

func TestOneOfInput(t *testing.T) {
	tom := "Tom"
	three := 3
	c := newClient(t)
	expectEqual(t, must(c.Queries.DescribePet(ctx(t), gl.Pet{Cat: &tom})).DescribePet, "cat:Tom", "cat")
	expectEqual(t, must(c.Queries.DescribePet(ctx(t), gl.Pet{Dog: &three})).DescribePet, "dog:3", "dog")
}

func TestDeprecatedFieldsArgumentsAndEnumValuesStillWork(t *testing.T) {
	a, b := "a", "b"
	r := must(newClient(t).Queries.Legacy(ctx(t), gl.LegacyOptions{WithReason: &a, Plain: &b})).Legacy
	expectEqual(t, *r.Old, "a", "old")
	expectEqual(t, *r.Older, "b", "older")
	expectEqual(t, *r.Mood, gl.MoodCalm, "mood")
}
