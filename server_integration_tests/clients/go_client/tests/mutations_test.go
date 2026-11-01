package tests

import (
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

var createArgs = gl.CreateArticleFieldArgs{LatestArticlesLimit: 2}

func TestCreateArticleReturnsCreatedArticleWithGivenInput(t *testing.T) {
	c := newClient(t)
	res := must(c.Mutations.CreateArticle(ctx(t), gl.CreateArticleInput{Title: "New Post", AuthorId: "2"}, createArgs))
	if res.CreateArticle.Title != "New Post" || res.CreateArticle.AuthorId != "2" || res.CreateArticle.Id == "" {
		t.Fatalf("unexpected article: %+v", res.CreateArticle)
	}
}

func TestUpdateArticleUpdatesTitleAndReturnsArticle(t *testing.T) {
	c := newClient(t)
	created := must(c.Mutations.CreateArticle(ctx(t), gl.CreateArticleInput{Title: "Original Title", AuthorId: "1"}, createArgs))
	res := must(c.Mutations.UpdateArticle(ctx(t),
		gl.UpdateArticleInput{Id: created.CreateArticle.Id, Title: gl.Ptr("Updated Title")},
		gl.UpdateArticleFieldArgs{LatestArticlesLimit: 2}))
	if res.UpdateArticle.Id != created.CreateArticle.Id || res.UpdateArticle.Title != "Updated Title" {
		t.Fatalf("unexpected article: %+v", res.UpdateArticle)
	}
}

func TestDeleteArticleReturnsTrueWhenArticleExists(t *testing.T) {
	c := newClient(t)
	created := must(c.Mutations.CreateArticle(ctx(t), gl.CreateArticleInput{Title: "To Delete", AuthorId: "1"}, createArgs))
	if !must(c.Mutations.DeleteArticle(ctx(t), created.CreateArticle.Id)).DeleteArticle {
		t.Fatal("expected true")
	}
}

func TestDeleteArticleReturnsFalseWhenArticleDoesNotExist(t *testing.T) {
	c := newClient(t)
	if must(c.Mutations.DeleteArticle(ctx(t), "missing-id")).DeleteArticle {
		t.Fatal("expected false")
	}
}

func TestAckPriorityEnumMutationArgument(t *testing.T) {
	c := newClient(t)
	if got := must(c.Mutations.AckPriority(ctx(t), gl.PriorityHigh)).AckPriority; got != "OK" {
		t.Fatalf("got %q", got)
	}
}
