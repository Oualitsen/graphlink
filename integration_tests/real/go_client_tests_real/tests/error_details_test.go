package tests

import (
	"reflect"
	"testing"
)

func TestErrorDetails(t *testing.T) {
	res := must(newClient(t).Queries.GetUserOrErrors(ctx(t), "missing"))
	if len(res.Errors) != 1 {
		t.Fatalf("errors=%v", res.Errors)
	}
	e := res.Errors[0]
	expectEqual(t, e.Message, "User not found: missing", "message")
	if !reflect.DeepEqual(e.Path, []any{"getUserOrErrors"}) {
		t.Fatalf("path=%v", e.Path)
	}
	expectEqual(t, e.Locations[0].Line, 1, "line")
	expectEqual(t, e.Extensions["code"], any("NOT_FOUND"), "code")
	expectEqual(t, e.Extensions["retryable"], any(false), "retryable")
	want := map[string]any{"id": "missing", "attempts": float64(3)}
	if !reflect.DeepEqual(e.Extensions["detail"], want) {
		t.Fatalf("detail=%#v", e.Extensions["detail"])
	}
}

func TestPartialDataWithAliasedError(t *testing.T) {
	res := must(newClient(t).Queries.PartialAliased(ctx(t)))
	if res.Data == nil || res.Data.Bad != nil {
		t.Fatalf("data=%+v", res.Data)
	}
	expectEqual(t, res.Data.Ok.Id, "user-1", "ok.id")
	if len(res.Errors) != 1 || !reflect.DeepEqual(res.Errors[0].Path, []any{"bad"}) {
		t.Fatalf("errors=%v", res.Errors)
	}
}
