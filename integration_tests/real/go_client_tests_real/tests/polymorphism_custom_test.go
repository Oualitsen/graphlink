package tests

import (
	"encoding/json"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func asMap(t *testing.T, value any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]any{}
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestCustomQueryInlineFragmentsOnEveryMemberOfAUnion(t *testing.T) {
	c := newClient(t)
	photo, _ := must(c.Queries.FetchAttachment(ctx(t), "ph1")).Attachment.(gl.Photo)
	video, _ := must(c.Queries.FetchAttachment(ctx(t), "v1")).Attachment.(gl.Video)
	document, _ := must(c.Queries.FetchAttachment(ctx(t), "d1")).Attachment.(gl.Document)
	expectEqual(t, photo.Width, 640, "width")
	expectEqual(t, video.Seconds, 30, "seconds")
	expectEqual(t, document.Pages, 12, "pages")
	if must(c.Queries.FetchAttachment(ctx(t), "nope")).Attachment != nil {
		t.Fatal("unknown attachment must decode to nil")
	}
}

func TestCustomQueryOneFragmentSharedByTwoRootFields(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.FetchArticleAndAttachment(ctx(t), "a1", "v1"))
	expectEqual(t, asMap(t, res.Article)["cover"].(map[string]any)["id"], any("ph1"), "cover id")
	attachment := asMap(t, res.Attachment)
	expectEqual(t, attachment["id"], any("v1"), "attachment id")
	expectEqual(t, attachment["seconds"], any(float64(30)), "seconds")
}

func TestDifferentShapesInterfaceSelectionWithInlineFragmentsAndASharedFragment(t *testing.T) {
	c := newClient(t)
	feed := must(c.Queries.FetchFeed(ctx(t))).Feed
	expectEqual(t, len(feed), 4, "feed size")
	first := asMap(t, feed[0])
	expectEqual(t, first["title"], any("Hello"), "title")
	expectEqual(t, first["cover"].(map[string]any)["url"], any("http://cdn/1.png"), "cover url")
	attachments := first["attachments"].([]any)
	expectEqual(t, len(attachments), 3, "attachments")
	expectEqual(t, attachments[1].(map[string]any)["id"], any("v1"), "second attachment")
	expectEqual(t, asMap(t, feed[1])["text"], any("Nice"), "comment text")
	if asMap(t, feed[2])["cover"] != nil {
		t.Fatal("second article has no cover")
	}
}

func TestDifferentShapesInterfaceSelectionThatNamesOnlySomeImplementers(t *testing.T) {
	c := newClient(t)
	article := asMap(t, must(c.Queries.FetchNode(ctx(t), "a1")).Node)
	expectEqual(t, article["title"], any("Hello"), "title")
	expectEqual(t, article["createdBy"], any("alice"), "createdBy")
	comment := asMap(t, must(c.Queries.FetchNode(ctx(t), "c1")).Node)
	expectEqual(t, comment["createdBy"], any("bob"), "createdBy")
	if _, has := comment["title"]; has {
		t.Fatal("a comment has no title")
	}
}

func TestDifferentShapesTwoQueriesSelectDifferentShapesOfTheSameUnion(t *testing.T) {
	c := newClient(t)
	photo := asMap(t, must(c.Queries.FetchPhotoParts(ctx(t), "ph1")).Attachment)
	expectEqual(t, photo["width"], any(float64(640)), "width")
	expectEqual(t, photo["url"], any("http://cdn/1.png"), "url")
	video := asMap(t, must(c.Queries.FetchPhotoParts(ctx(t), "v1")).Attachment)
	expectEqual(t, video["id"], any("v1"), "id")
	if _, has := video["seconds"]; has {
		t.Fatal("the partial selection must not carry seconds")
	}
	full, _ := must(c.Queries.FetchAttachment(ctx(t), "ph1")).Attachment.(gl.Photo)
	expectEqual(t, full.Width, 640, "full width")
}

func TestSubscriptionUnionStreamEmitsEachMember(t *testing.T) {
	c := clientOnNewWs(t)
	events := c.Subscriptions.AttachmentAdded(subscriptionContext(t))
	got := []gl.Attachment{
		firstEvent(t, events).Data.AttachmentAdded,
		firstEvent(t, events).Data.AttachmentAdded,
		firstEvent(t, events).Data.AttachmentAdded,
	}
	expectKinds(t, kinds(got), "Photo", "Video", "Document")
}

func TestSubscriptionInterfaceStreamEmitsEachImplementer(t *testing.T) {
	c := clientOnNewWs(t)
	events := c.Subscriptions.EntityPublished(subscriptionContext(t))
	got := []gl.Entity{
		firstEvent(t, events).Data.EntityPublished,
		firstEvent(t, events).Data.EntityPublished,
	}
	expectKinds(t, kinds(got), "Article", "Comment")
}

func TestSameFieldDifferentTypesAnAliasKeepsBothTypesReadable(t *testing.T) {
	c := newClient(t)
	phone := asMap(t, must(c.Queries.FetchGadget(ctx(t), "p1")).Gadget)
	laptop := asMap(t, must(c.Queries.FetchGadget(ctx(t), "l1")).Gadget)
	expectEqual(t, phone["size"], any(float64(6)), "phone size")
	expectEqual(t, laptop["laptopSize"], any("15 inch"), "laptop size")
	if must(c.Queries.FetchGadget(ctx(t), "nope")).Gadget != nil {
		t.Fatal("an unknown gadget must decode to nil")
	}
}

func TestSameFieldDifferentTypesAListOfBothMembers(t *testing.T) {
	c := newClient(t)
	gadgets := must(c.Queries.FetchGadgets(ctx(t))).Gadgets
	expectEqual(t, len(gadgets), 2, "size")
	expectEqual(t, asMap(t, gadgets[0])["size"], any(float64(6)), "phone size")
	expectEqual(t, asMap(t, gadgets[1])["laptopSize"], any("15 inch"), "laptop size")
}

func TestTypeInTwoUnionsPhotoDecodesThroughShareableAndAttachment(t *testing.T) {
	c := newClient(t)
	if _, ok := must(c.Queries.Shareable(ctx(t), "ph1")).Shareable.(gl.Photo); !ok {
		t.Fatal("ph1 through Shareable is not a Photo")
	}
	if _, ok := must(c.Queries.Attachment(ctx(t), "ph1")).Attachment.(gl.Photo); !ok {
		t.Fatal("ph1 through Attachment is not a Photo")
	}
}

func TestTypeInTwoUnionsPhoneDecodesThroughShareable(t *testing.T) {
	c := newClient(t)
	phone, ok := must(c.Queries.Shareable(ctx(t), "p1")).Shareable.(gl.Phone)
	if !ok {
		t.Fatal("p1 through Shareable is not a Phone")
	}
	expectEqual(t, phone.Model, "Pixel", "model")
	if must(c.Queries.Shareable(ctx(t), "nope")).Shareable != nil {
		t.Fatal("an unknown shareable must decode to nil")
	}
}
