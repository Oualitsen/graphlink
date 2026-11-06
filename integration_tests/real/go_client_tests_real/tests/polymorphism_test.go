package tests

import (
	"context"
	"sync/atomic"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func kinds[T any](values []T) []string {
	out := make([]string, len(values))
	for i, v := range values {
		switch any(v).(type) {
		case gl.Photo:
			out[i] = "Photo"
		case gl.Video:
			out[i] = "Video"
		case gl.Document:
			out[i] = "Document"
		case gl.Article:
			out[i] = "Article"
		case gl.Comment:
			out[i] = "Comment"
		case nil:
			out[i] = "nil"
		default:
			out[i] = "other"
		}
	}
	return out
}

func expectKinds(t *testing.T, actual []string, expected ...string) {
	t.Helper()
	expectEqual(t, len(actual), len(expected), "length")
	for i := range expected {
		expectEqual(t, actual[i], expected[i], "kind")
	}
}

func TestPolymorphismUnionMemberPerId(t *testing.T) {
	c := newClient(t)
	photo, isPhoto := must(c.Queries.Attachment(ctx(t), "ph1")).Attachment.(gl.Photo)
	if !isPhoto {
		t.Fatal("ph1 is not a Photo")
	}
	expectEqual(t, photo.Width, 640, "width")
	video, isVideo := must(c.Queries.Attachment(ctx(t), "v1")).Attachment.(gl.Video)
	if !isVideo {
		t.Fatal("v1 is not a Video")
	}
	expectEqual(t, video.Seconds, 30, "seconds")
	document, isDocument := must(c.Queries.Attachment(ctx(t), "d1")).Attachment.(gl.Document)
	if !isDocument {
		t.Fatal("d1 is not a Document")
	}
	expectEqual(t, document.Pages, 12, "pages")
}

func TestPolymorphismNullableUnionDecodesNil(t *testing.T) {
	c := newClient(t)
	if must(c.Queries.Attachment(ctx(t), "nope")).Attachment != nil {
		t.Fatal("expected nil")
	}
}

func TestPolymorphismListOfUnionMembers(t *testing.T) {
	c := newClient(t)
	expectKinds(t, kinds(must(c.Queries.Attachments(ctx(t))).Attachments), "Photo", "Video", "Document")
}

func TestPolymorphismNullElementsInAListOfUnions(t *testing.T) {
	c := newClient(t)
	expectKinds(t, kinds(must(c.Queries.AttachmentsNullable(ctx(t))).AttachmentsNullable), "Photo", "nil", "Document")
}

func TestPolymorphismUnionReturnedByAMutation(t *testing.T) {
	c := newClient(t)
	expectKinds(t, kinds([]gl.Attachment{
		must(c.Mutations.AddAttachment(ctx(t), "a1", "u", "photo")).AddAttachment,
		must(c.Mutations.AddAttachment(ctx(t), "a1", "u", "video")).AddAttachment,
		must(c.Mutations.AddAttachment(ctx(t), "a1", "u", "document")).AddAttachment,
	}), "Photo", "Video", "Document")
}

func TestPolymorphismServerErrorOnAUnionMutation(t *testing.T) {
	c := newClient(t)
	if _, err := c.Mutations.AddAttachment(ctx(t), "a1", "u", "bogus"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestPolymorphismListOfAnInterfaceImplementingAnotherInterface(t *testing.T) {
	c := newClient(t)
	feed := must(c.Queries.Feed(ctx(t))).Feed
	expectKinds(t, kinds(feed), "Article", "Comment", "Article", "Comment")
	created := make([]string, len(feed))
	for i, e := range feed {
		created[i] = e.GetCreatedBy()
	}
	expectKinds(t, created, "alice", "bob", "bob", "alice")
}

func TestPolymorphismNullableInterfaceReturnsEachImplementationOrNil(t *testing.T) {
	c := newClient(t)
	_, isArticle := must(c.Queries.Node(ctx(t), "a1")).Node.(gl.Article)
	_, isComment := must(c.Queries.Node(ctx(t), "c1")).Node.(gl.Comment)
	if !isArticle || !isComment {
		t.Fatalf("article=%v comment=%v", isArticle, isComment)
	}
	if must(c.Queries.Node(ctx(t), "zzz")).Node != nil {
		t.Fatal("expected nil")
	}
}

func TestPolymorphismUnionFieldAndListOfUnionsInsideAnObject(t *testing.T) {
	c := newClient(t)
	article := must(c.Queries.Article(ctx(t), "a1")).Article
	expectKinds(t, kinds([]gl.Attachment{article.Cover}), "Photo")
	expectKinds(t, kinds(article.Attachments), "Photo", "Video", "Document")
}

func TestPolymorphismNullPolymorphicFields(t *testing.T) {
	c := newClient(t)
	article := must(c.Queries.Article(ctx(t), "a2")).Article
	if article.Cover != nil || len(article.Attachments) != 0 || article.Related != nil {
		t.Fatalf("cover=%v attachments=%v related=%v", article.Cover, article.Attachments, article.Related)
	}
}

func TestPolymorphismNullElementsInAListOfInterfaces(t *testing.T) {
	c := newClient(t)
	expectKinds(t, kinds(must(c.Queries.Article(ctx(t), "a1")).Article.Related), "Comment", "nil")
}

func TestPolymorphismInterfaceFieldPointingBackAtAnImplementer(t *testing.T) {
	c := newClient(t)
	reply, isComment := must(c.Queries.Feed(ctx(t))).Feed[3].(gl.Comment)
	if !isComment {
		t.Fatal("expected a Comment")
	}
	parent, isArticle := reply.Parent.(gl.Article)
	if !isArticle {
		t.Fatal("expected an Article parent")
	}
	expectEqual(t, parent.Title, "Hello", "title")
}

func TestPolymorphismUnknownArticleIsAnError(t *testing.T) {
	c := newClient(t)
	if _, err := c.Queries.Article(ctx(t), "zzz"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestPolymorphismCapturedErrorsOnAUnionOperation(t *testing.T) {
	c := newClient(t)
	ok := must(c.Queries.AttachmentOrErrors(ctx(t), "ph1"))
	if ok.Errors != nil || ok.Data == nil {
		t.Fatalf("errors=%v data=%v", ok.Errors, ok.Data)
	}
	expectKinds(t, kinds([]gl.Attachment{ok.Data.AttachmentOrErrors}), "Photo")
	failed := must(c.Queries.AttachmentOrErrors(ctx(t), "boom"))
	if failed.Data == nil || failed.Data.AttachmentOrErrors != nil || len(failed.Errors) == 0 || failed.Errors[0].Message == "" {
		t.Fatalf("errors=%v data=%+v", failed.Errors, failed.Data)
	}
}

func TestPolymorphismCachedUnionOperationIsServedOnce(t *testing.T) {
	var calls atomic.Int32
	real := gl.NewGraphLinkHttpAdapter(httpURL(defaultPort))
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{
		Adapter: func(c context.Context, payload string) (string, error) {
			calls.Add(1)
			return real.Call(c, payload)
		},
		WsAdapter: gl.NewDefaultGraphLinkWebSocketAdapter(wsURL(defaultPort)),
	})
	if err != nil {
		t.Fatal(err)
	}
	first := must(client.Queries.GetCachedAttachment(ctx(t), "v1")).GetCachedAttachment
	second := must(client.Queries.GetCachedAttachment(ctx(t), "v1")).GetCachedAttachment
	expectKinds(t, kinds([]gl.Attachment{first, second}), "Video", "Video")
	expectEqual(t, int(calls.Load()), 1, "adapter calls")
}
