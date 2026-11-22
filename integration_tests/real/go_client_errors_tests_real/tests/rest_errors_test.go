package tests

import (
	"errors"
	"testing"

	gl "graphlink.dev/errorstests/generated"
)

func asRest(t *testing.T, err error) *gl.RestError {
	t.Helper()
	var e *gl.RestError
	if !errors.As(err, &e) {
		t.Fatalf("expected a RestError, got %T: %v", err, err)
	}
	return e
}

func TestRestSuccessfulCallReturnsData(t *testing.T) {
	item, err := newClient(t).Queries.Item(ctx(t), "1")
	if err != nil || item.Name != "Item 1" {
		t.Fatalf("unexpected result %+v, %v", item, err)
	}
}

func TestRestStatusOnlyErrorCarriesTheBodyFields(t *testing.T) {
	_, err := newClient(t).Queries.Item(ctx(t), "missing")
	var notFound *gl.ItemNotFound
	if !errors.As(err, &notFound) {
		t.Fatalf("expected ItemNotFound, got %T: %v", err, err)
	}
	if notFound.Id == nil || *notFound.Id != "missing" || notFound.Message != "Item missing not found" {
		t.Fatalf("unexpected fields %+v", notFound)
	}
}

func TestRestStatusWithItsOwnValue(t *testing.T) {
	_, err := newClient(t).Queries.Item(ctx(t), "conflict")
	var conflict *gl.ItemConflict
	if !errors.As(err, &conflict) || conflict.Reason != "duplicate" || conflict.Message != "Conflict" {
		t.Fatalf("expected ItemConflict, got %T: %v", err, err)
	}
}

func TestRestCustomFieldPath(t *testing.T) {
	_, err := newClient(t).Queries.Item(ctx(t), "rate")
	var limited *gl.RateLimited
	if !errors.As(err, &limited) || limited.RetryAfter != 30 {
		t.Fatalf("expected RateLimited, got %T: %v", err, err)
	}
}

func TestRestStatusOnlyDoesNotNeedAJsonBody(t *testing.T) {
	_, err := newClient(t).Queries.Item(ctx(t), "teapot")
	var teapot *gl.Teapot
	if !errors.As(err, &teapot) {
		t.Fatalf("expected Teapot, got %T: %v", err, err)
	}
}

func TestRestStatusOnlyWithAnHtmlBodyStillMatches(t *testing.T) {
	_, err := newClient(t).Queries.Item(ctx(t), "html-404")
	var notFound *gl.ItemNotFound
	if !errors.As(err, &notFound) || notFound.Id != nil {
		t.Fatalf("expected ItemNotFound without id, got %T: %v", err, err)
	}
}

func TestRestMutationThrowsItsError(t *testing.T) {
	_, err := newClient(t).Mutations.CreateItem(ctx(t), gl.ItemInput{Name: "dup"})
	var conflict *gl.ItemConflict
	if !errors.As(err, &conflict) || conflict.Reason != "name taken" {
		t.Fatalf("expected ItemConflict, got %T: %v", err, err)
	}
}

func TestRestMutationReturnsData(t *testing.T) {
	item, err := newClient(t).Mutations.CreateItem(ctx(t), gl.ItemInput{Name: "fresh"})
	if err != nil || item.Id != "new" {
		t.Fatalf("unexpected result %+v, %v", item, err)
	}
}

func TestRestFallsBackToRestError(t *testing.T) {
	cases := []struct {
		name   string
		id     string
		status int
	}{
		{"a body missing a required field", "conflict-no-reason", 409},
		{"a code the client does not know", "conflict-other", 409},
		{"a mistyped field", "rate-bad", 429},
		{"a proxy error with an HTML body", "bad-gateway", 502},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := newClient(t).Queries.Item(ctx(t), c.id)
			notDomain(t, err)
			if e := asRest(t, err); e.Status != c.status {
				t.Fatalf("expected status %d, got %d", c.status, e.Status)
			}
		})
	}
}

func TestRestOperationWithoutThrowsKeepsRestError(t *testing.T) {
	_, err := newClient(t).Queries.ItemPlain(ctx(t), "x")
	notDomain(t, err)
	if e := asRest(t, err); e.Status != 404 {
		t.Fatalf("expected 404, got %d", e.Status)
	}
}
