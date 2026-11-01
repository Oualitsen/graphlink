package tests

import (
	"errors"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestCapturedErrorsForUnknownId(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetUserOrErrors(ctx(t), "error-id"))
	if res.Data != nil || len(res.Errors) == 0 || res.Errors[0].Message == "" {
		t.Fatalf("data=%v errors=%v", res.Data, res.Errors)
	}
}

func TestCapturedErrorsSuccess(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetUserOrErrors(ctx(t), "user-1"))
	if res.Errors != nil || res.Data == nil {
		t.Fatalf("errors=%v data=%v", res.Errors, res.Data)
	}
	expectEqual(t, res.Data.GetUserOrErrors.Name, "Alice Smith", "name")
	expectEqual(t, res.Data.GetUserOrErrors.Id, "user-1", "id")
}

func TestPartialDataWithErrorsForNullableField(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.FindUserOrErrors(ctx(t), "error-id"))
	if len(res.Errors) == 0 || res.Data == nil || res.Data.FindUserOrErrors != nil {
		t.Fatalf("errors=%v data=%+v", res.Errors, res.Data)
	}
	missing := must(c.Queries.FindUserOrErrors(ctx(t), "missing"))
	if missing.Errors != nil || missing.Data == nil || missing.Data.FindUserOrErrors != nil {
		t.Fatalf("errors=%v data=%+v", missing.Errors, missing.Data)
	}
}

func TestCapturedErrorsOnMutations(t *testing.T) {
	c := newClient(t)
	bad := minimalInput()
	bad.Name = "error-user"
	res := must(c.Mutations.CreateUserOrErrors(ctx(t), bad))
	if len(res.Errors) == 0 || res.Data != nil {
		t.Fatalf("errors=%v data=%v", res.Errors, res.Data)
	}
	good := must(c.Mutations.CreateUserOrErrors(ctx(t), minimalInput()))
	if good.Errors != nil || good.Data == nil || good.Data.CreateUserOrErrors.Name != "Alice Smith" {
		t.Fatalf("errors=%v data=%+v", good.Errors, good.Data)
	}
}

func TestUncapturedErrorsReturnAnException(t *testing.T) {
	c := newClient(t)
	_, err := c.Queries.GetUser(ctx(t), "error-id")
	var exception *gl.GraphLinkException
	if !errors.As(err, &exception) || len(exception.Errors) == 0 || exception.Errors[0].Message == "" {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
}
