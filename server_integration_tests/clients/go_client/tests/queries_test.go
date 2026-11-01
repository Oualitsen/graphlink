package tests

import (
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

func TestGetAuthorReturnsAuthorById(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthor(ctx(t), "1", gl.GetAuthorFieldArgs{LatestArticlesLimit: 10}))
	if res.GetAuthor == nil || res.GetAuthor.Id != "1" || res.GetAuthor.Name != "Ramdane" {
		t.Fatalf("unexpected author: %+v", res.GetAuthor)
	}
}

func TestGetAuthorReturnsNullForUnknownId(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthor(ctx(t), "missing", gl.GetAuthorFieldArgs{LatestArticlesLimit: 10}))
	if res.GetAuthor != nil {
		t.Fatalf("expected nil, got %+v", res.GetAuthor)
	}
}

func titles(articles []gl.Article) map[string]bool {
	result := map[string]bool{}
	for _, a := range articles {
		result[a.Title] = true
	}
	return result
}

func TestArticlesResolvedViaBatchDataLoaderMapping(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthor(ctx(t), "1", gl.GetAuthorFieldArgs{LatestArticlesLimit: 10}))
	got := titles(res.GetAuthor.Articles)
	if !got["GraphLink Basics"] || !got["Advanced GraphLink"] {
		t.Fatalf("missing titles: %v", got)
	}
}

func TestLatestArticlesResolvedViaNonBatchMappingWithArguments(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthor(ctx(t), "1", gl.GetAuthorFieldArgs{LatestArticlesLimit: 10}))
	got := titles(res.GetAuthor.LatestArticles)
	if !got["GraphLink Basics"] || !got["Advanced GraphLink"] {
		t.Fatalf("missing titles: %v", got)
	}
}

func TestGetAuthorWithoutArticleDoesNotRequireLimitArgument(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthorWithoutArticle(ctx(t), "1"))
	if res.GetAuthor == nil || res.GetAuthor.Name != "Ramdane" {
		t.Fatalf("unexpected author: %+v", res.GetAuthor)
	}
}

func TestGetArticleReturnsArticleById(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetArticle(ctx(t), "1", gl.GetArticleFieldArgs{LatestArticlesLimit: 2}))
	if res.GetArticle.Id != "1" || res.GetArticle.Title != "GraphLink Basics" {
		t.Fatalf("unexpected article: %+v", res.GetArticle)
	}
}

func TestGetArticleAuthorResolvedViaNonBatchSchemaMapping(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetArticle(ctx(t), "1", gl.GetArticleFieldArgs{LatestArticlesLimit: 2}))
	if res.GetArticle.Author == nil || res.GetArticle.Author.Id != "1" || res.GetArticle.Author.Name != "Ramdane" {
		t.Fatalf("unexpected author: %+v", res.GetArticle.Author)
	}
}

func TestGetAuthorAndArticleResolvesBothRootFields(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.GetAuthorAndArticle(ctx(t), "1", "3", gl.GetAuthorAndArticleFieldArgs{LatestArticlesLimit: 1}))
	if res.Author.Id != "1" || len(res.Author.LatestArticles) != 1 {
		t.Fatalf("unexpected author: %+v", res.Author)
	}
	if res.Article.Id != "3" || res.Article.Title != "Alice's First Post" {
		t.Fatalf("unexpected article: %+v", res.Article)
	}
}

func TestListAuthorsReturnsAllAuthors(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.ListAuthors(ctx(t), gl.ListAuthorsFieldArgs{LatestArticlesLimit: 10}))
	ids := map[string]bool{}
	for _, a := range res.ListAuthors {
		ids[a.Id] = true
	}
	if !ids["1"] || !ids["2"] {
		t.Fatalf("missing authors: %v", ids)
	}
}

func TestListArticlesReturnsAllArticles(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.ListArticles(ctx(t), gl.ListArticlesFieldArgs{LatestArticlesLimit: 2}))
	found := false
	for _, a := range res.ListArticles {
		found = found || a.Id == "1"
	}
	if !found {
		t.Fatal("article 1 missing")
	}
}
