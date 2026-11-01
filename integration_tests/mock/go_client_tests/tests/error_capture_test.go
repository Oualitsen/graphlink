package tests

import (
	"errors"
	"testing"

	gl "graphlink.dev/mocktests/generated"
)

func TestCapturedErrorsOnQueries(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterErrors("getUserOrErrors", graphQLError)
	res := must(h.client.Queries.GetUserOrErrors(h.ctx, "user-1"))
	if res.Data != nil || len(res.Errors) == 0 {
		t.Fatalf("data=%v errors=%v", res.Data, res.Errors)
	}
	expectEqual(t, res.Errors[0].Message, "Not found", "message")

	h.adapter.RegisterData("getUserOrErrors", object{"getUserOrErrors": userAliceJson})
	ok := must(h.client.Queries.GetUserOrErrors(h.ctx, "user-1"))
	if ok.Errors != nil || ok.Data == nil {
		t.Fatalf("errors=%v data=%v", ok.Errors, ok.Data)
	}
	expectEqual(t, ok.Data.GetUserOrErrors.Name, "Alice Smith", "name")
	expectEqual(t, ok.Data.GetUserOrErrors.Id, "user-1", "id")
}

func TestCapturedErrorsOnFindUser(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterErrors("findUserOrErrors", graphQLError)
	res := must(h.client.Queries.FindUserOrErrors(h.ctx, "user-1"))
	if res.Data != nil || len(res.Errors) == 0 {
		t.Fatalf("data=%v errors=%v", res.Data, res.Errors)
	}
	expectEqual(t, res.Errors[0].Message, "Not found", "message")
}

func TestCapturedErrorsOnMutations(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterErrors("createUserOrErrors", graphQLError)
	res := must(h.client.Mutations.CreateUserOrErrors(h.ctx, minimalInput()))
	if res.Data != nil || len(res.Errors) == 0 {
		t.Fatalf("data=%v errors=%v", res.Data, res.Errors)
	}
	expectEqual(t, res.Errors[0].Message, "Not found", "message")

	h.adapter.RegisterData("createUserOrErrors", object{"createUserOrErrors": userAliceJson})
	ok := must(h.client.Mutations.CreateUserOrErrors(h.ctx, minimalInput()))
	if ok.Errors != nil || ok.Data == nil {
		t.Fatalf("errors=%v data=%v", ok.Errors, ok.Data)
	}
	expectEqual(t, ok.Data.CreateUserOrErrors.Name, "Alice Smith", "name")
}

func TestUncapturedErrorsAreReturnedAsAnException(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterErrors("getUser", graphQLError)
	_, err := h.client.Queries.GetUser(h.ctx, "user-1")
	var exception *gl.GraphLinkException
	if !errors.As(err, &exception) {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
	expectEqual(t, exception.Errors[0].Message, "Not found", "message")
}
