package tests

import (
	"context"
	"errors"
	"testing"
	"time"

	gl "graphlink.dev/errorstests/generated"
)

const url = "http://127.0.0.1:9930/graphql"

func newClient(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{URL: url, RestBaseURL: "http://127.0.0.1:9930"})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	return c
}

func exception(t *testing.T, err error) *gl.GraphLinkException {
	t.Helper()
	var e *gl.GraphLinkException
	if !errors.As(err, &e) {
		t.Fatalf("expected a GraphLinkException, got %T: %v", err, err)
	}
	return e
}

func notDomain(t *testing.T, err error) {
	t.Helper()
	var domain *gl.GraphLinkDomainError
	if errors.As(err, &domain) {
		t.Fatalf("did not expect a domain error: %v", err)
	}
}

func TestSuccessfulQueryReturnsData(t *testing.T) {
	res, err := newClient(t).Queries.Article(ctx(t), "1")
	if err != nil || res.Article == nil || res.Article.Id != "1" {
		t.Fatalf("unexpected result %+v, %v", res, err)
	}
}

func TestDeclaredErrorIsReturnedAsItsType(t *testing.T) {
	_, err := newClient(t).Queries.Article(ctx(t), "missing")
	var notFound *gl.ArticleNotFound
	if !errors.As(err, &notFound) {
		t.Fatalf("expected ArticleNotFound, got %T: %v", err, err)
	}
	if notFound.Id != "missing" || notFound.Message != "Article missing not found" {
		t.Fatalf("unexpected fields %+v", notFound)
	}
}

func TestCustomFieldAndValue(t *testing.T) {
	_, err := newClient(t).Queries.Article(ctx(t), "forbidden")
	var forbidden *gl.Forbidden
	if !errors.As(err, &forbidden) || forbidden.Message != "No access" {
		t.Fatalf("expected Forbidden, got %T: %v", err, err)
	}
}

func TestErrorOfAnotherRootField(t *testing.T) {
	_, err := newClient(t).Queries.Secret(ctx(t))
	var forbidden *gl.Forbidden
	if !errors.As(err, &forbidden) {
		t.Fatalf("expected Forbidden, got %T: %v", err, err)
	}
}

func TestFallbacksKeepTheException(t *testing.T) {
	for _, id := range []string{"other-code", "no-field", "no-path", "no-extensions"} {
		_, err := newClient(t).Queries.Article(ctx(t), id)
		exception(t, err)
		notDomain(t, err)
	}
}

func TestUnknownCodeKeepsItsMessage(t *testing.T) {
	_, err := newClient(t).Queries.Article(ctx(t), "other-code")
	if exception(t, err).Errors[0].Message != "A new error" {
		t.Fatal("the original error was lost")
	}
}

func TestOperationWithoutThrowsKeepsTheException(t *testing.T) {
	_, err := newClient(t).Queries.Plain(ctx(t), "1")
	exception(t, err)
	notDomain(t, err)
}

func TestCombinedQueryKeepsTheException(t *testing.T) {
	_, err := newClient(t).Queries.Pair(ctx(t))
	e := exception(t, err)
	if len(e.Errors) != 1 || e.Errors[0].Path[0] != "first" {
		t.Fatalf("unexpected errors %+v", e.Errors)
	}
}

func TestCaptureErrorsReturnsTheErrors(t *testing.T) {
	res, err := newClient(t).Queries.Captured(ctx(t))
	if err != nil || len(res.Errors) != 1 || res.Errors[0].Extensions["code"] != "ArticleNotFound" {
		t.Fatalf("unexpected result %+v, %v", res, err)
	}
}

func TestMutationReturnsData(t *testing.T) {
	res, err := newClient(t).Mutations.CreateArticle(ctx(t), gl.ArticleInput{Title: "fresh"})
	if err != nil || res.CreateArticle == nil || res.CreateArticle.Id != "fresh" {
		t.Fatalf("unexpected result %+v, %v", res, err)
	}
}

func TestMutationErrorCarriesAListField(t *testing.T) {
	_, err := newClient(t).Mutations.CreateArticle(ctx(t), gl.ArticleInput{Title: "taken"})
	var taken *gl.TitleTaken
	if !errors.As(err, &taken) || taken.Title != "taken" || len(taken.Suggestions) != 1 || taken.Suggestions[0] != "taken-2" {
		t.Fatalf("expected TitleTaken, got %T: %v", err, err)
	}
}

func TestMutationErrorWithEnumAndOptionalField(t *testing.T) {
	_, err := newClient(t).Mutations.CreateArticle(ctx(t), gl.ArticleInput{Title: "banned"})
	var banned *gl.Banned
	if !errors.As(err, &banned) || banned.Reason != gl.ReasonSpam || banned.Until == nil || *banned.Until != 5 {
		t.Fatalf("expected Banned, got %T: %v", err, err)
	}
}
