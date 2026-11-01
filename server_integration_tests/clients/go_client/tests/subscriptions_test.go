package tests

import (
	"context"
	"testing"
	"time"

	gl "graphlink.dev/serverintegration/generated"
)

func subscriptionContext(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	return c
}

func TestArticleCreatedEmitsWhenAnArticleIsCreated(t *testing.T) {
	c := newClient(t)
	events := c.Subscriptions.ArticleCreated(subscriptionContext(t), gl.ArticleCreatedFieldArgs{LatestArticlesLimit: 2})
	time.Sleep(500 * time.Millisecond)
	created := must(c.Mutations.CreateArticle(ctx(t), gl.CreateArticleInput{Title: "Subscribed Post", AuthorId: "1"}, createArgs))
	event := firstEvent(t, events)
	if event.Err != nil {
		t.Fatal(event.Err)
	}
	if event.Data.ArticleCreated.Id != created.CreateArticle.Id || event.Data.ArticleCreated.Title != "Subscribed Post" {
		t.Fatalf("unexpected event: %+v", event.Data.ArticleCreated)
	}
}

func TestArticleUpdatedEmitsWhenTheMatchingArticleIsUpdated(t *testing.T) {
	c := newClient(t)
	created := must(c.Mutations.CreateArticle(ctx(t), gl.CreateArticleInput{Title: "Will Update", AuthorId: "2"}, createArgs))
	events := c.Subscriptions.ArticleUpdated(subscriptionContext(t), created.CreateArticle.Id, gl.ArticleUpdatedFieldArgs{LatestArticlesLimit: 2})
	time.Sleep(500 * time.Millisecond)
	updated := must(c.Mutations.UpdateArticle(ctx(t),
		gl.UpdateArticleInput{Id: created.CreateArticle.Id, Title: gl.Ptr("Updated via subscription")},
		gl.UpdateArticleFieldArgs{LatestArticlesLimit: 2}))
	event := firstEvent(t, events)
	if event.Err != nil {
		t.Fatal(event.Err)
	}
	if event.Data.ArticleUpdated.Id != updated.UpdateArticle.Id || event.Data.ArticleUpdated.Title != "Updated via subscription" {
		t.Fatalf("unexpected event: %+v", event.Data.ArticleUpdated)
	}
}

func TestCancellingTheContextClosesTheChannel(t *testing.T) {
	c := newClient(t)
	cancelCtx, cancel := context.WithCancel(context.Background())
	events := c.Subscriptions.ArticleDeleted(cancelCtx)
	time.Sleep(300 * time.Millisecond)
	cancel()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case event, ok := <-events:
			if !ok {
				return
			}
			t.Logf("event before close: %+v", event)
		case <-deadline:
			t.Fatal("channel was not closed after cancel")
		}
	}
}
