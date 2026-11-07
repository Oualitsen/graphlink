package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func reservedFields(r gl.Reserved) map[string]string {
	return map[string]string{
		"type": r.Type2, "default": r.Default, "in": r.In, "is": r.Is, "var": r.Var, "val": r.Val,
		"fun": r.Fun, "new": r.New, "import": r.Import, "return": r.Return, "object": r.Object,
		"from": r.From, "None": r.None, "True": r.True, "func": r.Func, "range": r.Range,
		"self": r.Self2, "Self": r.Self, "init": r.Init, "Type": r.Type, "Protocol": r.Protocol,
		"async": r.Async, "await": r.Await, "package": r.Package, "interface": r.Interface,
		"enum": r.Enum, "null": r.Null,
	}
}

func expectEchoed(t *testing.T, fields map[string]string) {
	t.Helper()
	expectEqual(t, len(fields), 27, "field count")
	for wire, value := range fields {
		expectEqual(t, value, "v:"+wire, wire)
	}
}

func TestReservedWordsAsArgumentNames(t *testing.T) {
	r := must(newClient(t).Queries.ReservedEcho(ctx(t),
		"v:type", "v:default", "v:in", "v:is", "v:var", "v:val", "v:fun", "v:new", "v:import", "v:return",
		"v:object", "v:from", "v:None", "v:True", "v:func", "v:range", "v:self", "v:Self", "v:init",
		"v:Type", "v:Protocol", "v:async", "v:await", "v:package", "v:interface", "v:enum", "v:null",
	)).ReservedEcho
	expectEchoed(t, reservedFields(r))
}

func TestReservedWordsAsInputAndResponseFields(t *testing.T) {
	r := must(newClient(t).Queries.ReservedEchoInput(ctx(t), gl.ReservedInput{
		Type2: "v:type", Default: "v:default", In: "v:in", Is: "v:is", Var: "v:var", Val: "v:val",
		Fun: "v:fun", New: "v:new", Import: "v:import", Return: "v:return", Object: "v:object",
		From: "v:from", None: "v:None", True: "v:True", Func: "v:func", Range: "v:range",
		Self2: "v:self", Self: "v:Self", Init: "v:init", Type: "v:Type", Protocol: "v:Protocol",
		Async: "v:async", Await: "v:await", Package: "v:package", Interface: "v:interface",
		Enum: "v:enum", Null: "v:null",
	})).ReservedEchoInput
	expectEchoed(t, reservedFields(r))
}

func TestReservedWordsAsOperationNames(t *testing.T) {
	q := newClient(t).Queries
	expectEqual(t, must(q.Import(ctx(t), "a")).Import, "a", "import")
	expectEqual(t, must(q.Default(ctx(t), "b")).Default, "b", "default")
	expectEqual(t, must(q.New(ctx(t), "c")).New, "c", "new")
	expectEqual(t, must(q.Func(ctx(t), "d")).Func, "d", "func")
	expectEqual(t, must(q.None(ctx(t), "e")).None, "e", "None")
	expectEqual(t, must(q.Self(ctx(t), "f")).Self, "f", "self")
}

var literals = []gl.Literal{
	gl.LiteralDefault, gl.LiteralClass, gl.LiteralNone, gl.LiteralTrue,
	gl.LiteralNil, gl.LiteralUndefined, gl.LiteralNaN, gl.LiteralSelf,
}

func TestLiteralLookingEnumValuesDecode(t *testing.T) {
	expectDeep(t, must(newClient(t).Queries.Literals(ctx(t))).Literals, literals, "literals")
}

func TestLiteralLookingEnumValuesRoundTrip(t *testing.T) {
	for _, v := range literals {
		expectEqual(t, must(newClient(t).Queries.LiteralEcho(ctx(t), v, literals)).LiteralEcho, v, string(v))
	}
}

func TestStdlibClashingTypeNames(t *testing.T) {
	c := must(newClient(t).Queries.Clashes(ctx(t))).Clashes
	expectEqual(t, c.Error.Id, "error-1", "error")
	expectEqual(t, c.Response.Id, "response-1", "response")
	expectEqual(t, c.Request.Id, "request-1", "request")
	expectEqual(t, c.List.Id, "list-1", "list")
	expectEqual(t, c.Map.Id, "map-1", "map")
	expectEqual(t, c.Object.Id, "object-1", "object")
	expectEqual(t, c.Optional.Id, "optional-1", "optional")
	expectEqual(t, c.Date.Id, "date-1", "date")
	expectEqual(t, c.Result.Id, "result-1", "result")
	expectEqual(t, c.Void.Id, "void-1", "void")
}

func TestOddNamesRoundTrip(t *testing.T) {
	r := must(newClient(t).Queries.OddEcho(ctx(t), gl.OddInput{
		UserId: "user_id", UserId2: "userId", UrlValue: "URLValue", HttpServer: "HTTPServer",
		Leading: "_leading", Trailing: "trailing_", V2Name: "v2_name", IsActive: "isActive",
		Active: "active", GetX: "getX", X: "x",
	})).OddEcho
	expectDeep(t, []string{r.UserId, r.UserId2, r.UrlValue, r.HttpServer, r.Leading, r.Trailing, r.V2Name, r.IsActive, r.Active, r.GetX, r.X},
		[]string{"user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_", "v2_name", "isActive", "active", "getX", "x"}, "odd")
}
