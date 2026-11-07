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
		case gl.Album:
			out[i] = "Album"
		case gl.Playlist:
			out[i] = "Playlist"
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

func TestPolymorphismInterfaceFieldArgumentReachesEveryImplementer(t *testing.T) {
	c := newClient(t)
	album, isAlbum := must(c.Queries.Listing(ctx(t), "al1", gl.ListingFieldArgs{ItemsLimit: 2})).Listing.(gl.Album)
	if !isAlbum {
		t.Fatal("expected an Album")
	}
	expectEqual(t, album.Year, 2020, "year")
	expectKinds(t, kinds(album.Items), "Photo", "Video")
	playlist, isPlaylist := must(c.Queries.Listing(ctx(t), "pl1", gl.ListingFieldArgs{ItemsLimit: 5})).Listing.(gl.Playlist)
	if !isPlaylist {
		t.Fatal("expected a Playlist")
	}
	expectEqual(t, playlist.Tracks, 12, "tracks")
	expectKinds(t, kinds(playlist.Items), "Video", "Document")
}

func TestPolymorphismInterfaceFieldArgumentOfZeroYieldsEmptyLists(t *testing.T) {
	c := newClient(t)
	listing := must(c.Queries.Listing(ctx(t), "al1", gl.ListingFieldArgs{ItemsLimit: 0})).Listing
	expectEqual(t, len(listing.GetItems()), 0, "items")
}

func TestPolymorphismInterfaceFieldReturnsTheOtherImplementerOrNil(t *testing.T) {
	c := newClient(t)
	summer := must(c.Queries.Listing(ctx(t), "al1", gl.ListingFieldArgs{ItemsLimit: 1})).Listing
	related, isPlaylist := summer.GetRelated().(gl.Playlist)
	if !isPlaylist {
		t.Fatal("expected a Playlist")
	}
	expectEqual(t, related.Tracks, 12, "tracks")
	winter := must(c.Queries.Listing(ctx(t), "al2", gl.ListingFieldArgs{ItemsLimit: 1})).Listing
	if winter.GetRelated() != nil {
		t.Fatal("expected nil")
	}
}

func TestPolymorphismInterfaceWithUnknownIdDecodesNil(t *testing.T) {
	c := newClient(t)
	if must(c.Queries.Listing(ctx(t), "nope", gl.ListingFieldArgs{ItemsLimit: 1})).Listing != nil {
		t.Fatal("expected nil")
	}
}

func TestPolymorphismListOfTheInterfaceDecodesEachImplementer(t *testing.T) {
	c := newClient(t)
	listings := must(c.Queries.Listings(ctx(t), gl.ListingsFieldArgs{ItemsLimit: 1})).Listings
	expectKinds(t, kinds(listings), "Album", "Playlist", "Album")
	for _, l := range listings {
		expectEqual(t, len(l.GetItems()), 1, "items")
	}
}

func TestPolymorphismSingleMemberUnionDecodesToTheMember(t *testing.T) {
	c := newClient(t)
	solo, isAlbum := must(c.Queries.Solo(ctx(t), gl.SoloFieldArgs{ItemsLimit: 1})).Solo.(gl.Album)
	if !isAlbum {
		t.Fatal("expected an Album")
	}
	expectEqual(t, solo.Title, "Summer", "title")
}

func TestPolymorphismSharedFieldSameTypeIsReadableOnTheUnion(t *testing.T) {
	c := newClient(t)
	attachments := must(c.Queries.Attachments(ctx(t))).Attachments
	ids := make([]string, len(attachments))
	urls := make([]string, len(attachments))
	for i, a := range attachments {
		ids[i] = a.GetId()
		urls[i] = a.GetUrl()
	}
	expectKinds(t, ids, "ph1", "v1", "d1")
	expectKinds(t, urls, "http://cdn/1.png", "http://cdn/1.mp4", "http://cdn/1.pdf")
}

func TestPolymorphismSelectionSharingOnlySomeFieldsExposesJustThose(t *testing.T) {
	c := newClient(t)
	expectEqual(t, must(c.Queries.FetchPhotoParts(ctx(t), "ph1")).Attachment.GetId(), "ph1", "photo id")
	expectEqual(t, must(c.Queries.FetchPhotoParts(ctx(t), "v1")).Attachment.GetId(), "v1", "video id")
}

func TestPolymorphismUnionOfTwoTypesSharesOnlyId(t *testing.T) {
	c := newClient(t)
	expectEqual(t, must(c.Queries.Shareable(ctx(t), "ph1")).Shareable.GetId(), "ph1", "photo id")
	expectEqual(t, must(c.Queries.Shareable(ctx(t), "p1")).Shareable.GetId(), "p1", "phone id")
}

func TestPolymorphismMemberReturnedDirectlyKeepsTheFullType(t *testing.T) {
	c := newClient(t)
	photo := must(c.Queries.Photo(ctx(t), "ph1")).Photo
	expectEqual(t, photo.Id, "ph1", "id")
	expectEqual(t, photo.Url, "http://cdn/1.png", "url")
	expectEqual(t, photo.Width, 640, "width")
	if must(c.Queries.Photo(ctx(t), "nope")).Photo != nil {
		t.Fatal("expected nil")
	}
}

func TestPolymorphismPartialSelectionOfTheSameTypeDoesNotReplaceIt(t *testing.T) {
	c := newClient(t)
	expectEqual(t, must(c.Queries.FetchPhotoWidth(ctx(t), "ph1")).Photo.Width, 640, "width")
	member, isPhoto := must(c.Queries.FetchPhotoUrl(ctx(t), "ph1")).Attachment.(gl.Photo_Url)
	if !isPhoto {
		t.Fatal("expected a Photo_Url")
	}
	expectEqual(t, member.Url, "http://cdn/1.png", "url")
	if _, isVideo := must(c.Queries.FetchPhotoUrl(ctx(t), "v1")).Attachment.(gl.Video_Id); !isVideo {
		t.Fatal("expected a Video_Id")
	}
}

func TestPolymorphismInterfaceFragmentMixedWithConcreteOnes(t *testing.T) {
	c := newClient(t)
	results := must(c.Queries.SearchMixed(ctx(t), "x")).Search
	expectEqual(t, len(results), 2, "length")
	expectEqual(t, results[0].GetId(), "user-1", "first id")
	expectEqual(t, results[1].GetId(), "post-1", "second id")
	user, isUser := results[0].(gl.UserResult_IdName)
	post, isPost := results[1].(gl.PostResult)
	if !isUser || !isPost {
		t.Fatalf("user=%v post=%v", isUser, isPost)
	}
	expectEqual(t, user.Name, "Alice Smith", "name")
	expectEqual(t, post.Title, "Hello World", "title")
}

func cachedNodeTitle(t *testing.T, c *gl.GraphLinkClient) string {
	return must(c.Queries.GetCachedNode(ctx(t), "a1")).GetCachedNode.(gl.Article).Title
}

func cachedVideoSeconds(t *testing.T, c *gl.GraphLinkClient) int {
	return must(c.Queries.GetCachedAttachment(ctx(t), "v1")).GetCachedAttachment.(gl.Video).Seconds
}

func TestPolymorphismCachedInterfaceResultIsServedFromTheCache(t *testing.T) {
	c := newClient(t)
	expectEqual(t, cachedNodeTitle(t, c), cachedNodeTitle(t, c), "title")
}

func TestPolymorphismInvalidatingTheTagOfACachedInterfaceFetchesItAgain(t *testing.T) {
	c := newClient(t)
	before := cachedNodeTitle(t, c)
	must(c.Mutations.EvictNodes(ctx(t)))
	if cachedNodeTitle(t, c) == before {
		t.Fatal("expected a new fetch")
	}
}

func TestPolymorphismInvalidatingTheTagOfACachedUnionFetchesItAgain(t *testing.T) {
	c := newClient(t)
	before := cachedVideoSeconds(t, c)
	expectEqual(t, cachedVideoSeconds(t, c), before, "cached seconds")
	must(c.Mutations.EvictAttachments(ctx(t)))
	if cachedVideoSeconds(t, c) == before {
		t.Fatal("expected a new fetch")
	}
}

func TestPolymorphismInvalidatingAnotherTagLeavesTheCachedUnionAlone(t *testing.T) {
	c := newClient(t)
	before := cachedVideoSeconds(t, c)
	must(c.Mutations.EvictNodes(ctx(t)))
	expectEqual(t, cachedVideoSeconds(t, c), before, "cached seconds")
}

func TestPolymorphismInterfaceSelectionWithoutImplementerDecodesEveryImplementer(t *testing.T) {
	c := newClient(t)
	expectEqual(t, must(c.Queries.FetchNodeId(ctx(t), "a1")).Node.GetId(), "a1", "article id")
	expectEqual(t, must(c.Queries.FetchNodeId(ctx(t), "c1")).Node.GetId(), "c1", "comment id")
}

func TestPolymorphismInterfaceSelectionWithoutImplementerUnknownIdIsNil(t *testing.T) {
	c := newClient(t)
	if must(c.Queries.FetchNodeId(ctx(t), "nope")).Node != nil {
		t.Fatal("expected nil")
	}
}
