package tests

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func ptr[T any](v T) *T { return &v }

func typeName(v any) string {
	if v == nil {
		return "nil"
	}
	return strings.TrimPrefix(fmt.Sprintf("%T", v), "generated.")
}

func typeNames[T any](values []T) []string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = typeName(v)
	}
	return out
}

func expectNames(t *testing.T, actual []string, expected ...string) {
	t.Helper()
	expectEqual(t, strings.Join(actual, ","), strings.Join(expected, ","), "types")
}

func decodedField(t *testing.T, value any, name string) any {
	t.Helper()
	field := reflect.ValueOf(value).FieldByName(name)
	if !field.IsValid() {
		t.Fatalf("%T has no field %s", value, name)
	}
	if field.Kind() == reflect.Ptr {
		field = field.Elem()
	}
	return field.Interface()
}

func asList(t *testing.T, value any) []any {
	t.Helper()
	list, ok := value.([]any)
	if !ok {
		t.Fatalf("expected a list, got %T", value)
	}
	return list
}

func asObject(t *testing.T, value any) map[string]any {
	t.Helper()
	object, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("expected an object, got %T", value)
	}
	return object
}

// ── nested lists of polymorphic types ───────────────────────────────────────

func TestNestedListsOfUnionsAndInterfaces(t *testing.T) {
	c := newClient(t)
	grid := must(c.Queries.Grid(ctx(t))).Grid
	expectEqual(t, len(grid.Cells), 3, "cells")
	expectNames(t, typeNames(grid.Cells[0]), "Photo", "nil")
	expectNames(t, typeNames(grid.Cells[1]), "Video")
	expectEqual(t, len(grid.Cells[2]), 0, "empty row")
	expectNames(t, typeNames(grid.Rows[0]), "Article", "Comment")
	expectNames(t, typeNames(grid.Rows[1]), "Article")
	expectNames(t, typeNames(grid.Maybe[0]), "Photo", "Document")
}

func TestNestedListsEmptyAndNullStayAsTheyAre(t *testing.T) {
	c := newClient(t)
	grid := must(c.Queries.Grid(ctx(t), gl.GridOptions{Empty: ptr(true)})).Grid
	expectEqual(t, len(grid.Cells), 0, "cells")
	expectEqual(t, len(grid.Rows), 0, "rows")
	if grid.Maybe != nil {
		t.Fatal("a null list must decode to nil")
	}
}

func TestNestedListsProjectedSelection(t *testing.T) {
	c := newClient(t)
	grid := asMap(t, must(c.Queries.GridProjected(ctx(t))).Grid)
	cells := asList(t, grid["cells"])
	expectEqual(t, asObject(t, asList(t, cells[0])[0])["width"], any(float64(640)), "width")
	expectEqual(t, asList(t, cells[0])[1], nil, "null element")
	expectEqual(t, asObject(t, asList(t, cells[1])[0])["seconds"], any(float64(30)), "seconds")
	rows := asList(t, asList(t, grid["rows"])[0])
	expectEqual(t, asObject(t, rows[0])["id"], any("a1"), "article")
	expectEqual(t, asObject(t, rows[0])["title"], any("Hello"), "title")
	expectEqual(t, asObject(t, rows[1])["text"], any("Nice"), "text")
	maybe := asList(t, asList(t, grid["maybe"])[0])
	expectEqual(t, asObject(t, maybe[0])["url"], any("http://cdn/1.png"), "url")
	expectEqual(t, asObject(t, maybe[1])["id"], any("d1"), "document")
}

// ── custom scalars inside polymorphic types ─────────────────────────────────

func TestScalarsInAListOfAUnion(t *testing.T) {
	c := newClient(t)
	moments := must(c.Queries.Moments(ctx(t))).Moments
	stamp, _ := moments[0].(gl.Stamp)
	expectEqual(t, stamp.At, "2026-01-02T03:04:05Z", "at")
	expectEqual(t, stamp.Big, int64(4294967296), "big")
	span, _ := moments[1].(gl.Span)
	expectEqual(t, *span.Until, "2026-02-04", "until")
	expectEqual(t, *span.Opaque, "opaque:o-9", "opaque")
	expectEqual(t, span.Dts[0], "2026-03-04T05:06:07Z", "dts")
}

func TestScalarsInAListOfAnInterface(t *testing.T) {
	c := newClient(t)
	timed := must(c.Queries.Timed(ctx(t))).Timed
	expectNames(t, typeNames(timed), "Span", "Stamp")
	span, _ := timed[0].(gl.Span)
	stamp, _ := timed[1].(gl.Stamp)
	expectEqual(t, *span.Opaque, "opaque:o-9", "opaque")
	expectEqual(t, stamp.Big, int64(4294967296), "big")
}

func TestScalarsInAProjectedUnion(t *testing.T) {
	c := newClient(t)
	moments := must(c.Queries.MomentsProjected(ctx(t))).Moments
	first, second := asMap(t, moments[0]), asMap(t, moments[1])
	expectEqual(t, first["at"], any("2026-01-02T03:04:05Z"), "at")
	expectEqual(t, first["big"], any(float64(4294967296)), "big")
	expectEqual(t, decodedField(t, moments[1], "Opaque"), any("opaque:o-9"), "opaque")
	expectEqual(t, second["until"], any("2026-02-04"), "until")
}

func TestScalarsInAProjectedInterface(t *testing.T) {
	c := newClient(t)
	timed := must(c.Queries.TimedProjected(ctx(t))).Timed
	first, second := asMap(t, timed[0]), asMap(t, timed[1])
	expectEqual(t, first["at"], any("2026-02-03T04:05:06Z"), "span at")
	expectEqual(t, second["at"], any("2026-01-02T03:04:05Z"), "stamp at")
	expectEqual(t, decodedField(t, timed[0], "Opaque"), any("opaque:o-9"), "opaque")
	expectEqual(t, second["big"], any(float64(4294967296)), "big")
}

// ── a union member that points back at its union ────────────────────────────

func TestRecursiveUnionThreeLevelsDeep(t *testing.T) {
	c := newClient(t)
	chain := asMap(t, must(c.Queries.ChainDeep(ctx(t), "l1")).Chain)
	next := asObject(t, chain["next"])
	last := asObject(t, next["next"])
	expectEqual(t, chain["id"], any("l1"), "first")
	expectEqual(t, next["id"], any("l2"), "second")
	expectEqual(t, last["id"], any("e1"), "third")
	expectEqual(t, last["reason"], any("done"), "reason")
}

func TestRecursiveUnionEndDirectlyAndUnknownId(t *testing.T) {
	c := newClient(t)
	expectEqual(t, asMap(t, must(c.Queries.ChainDeep(ctx(t), "e1")).Chain)["reason"], any("done"), "reason")
	if must(c.Queries.ChainDeep(ctx(t), "nope")).Chain != nil {
		t.Fatal("an unknown id must decode to nil")
	}
}

func TestRecursiveUnionAllFieldsStopsAfterOneLevel(t *testing.T) {
	c := newClient(t)
	chain := asMap(t, must(c.Queries.Chain(ctx(t), "l1")).Chain)
	expectEqual(t, chain["id"], any("l1"), "first")
	expectEqual(t, asObject(t, chain["next"])["id"], any("l2"), "second")
}

// ── lists of unions and interfaces in every operation kind ──────────────────

func cachedListVideoSeconds(t *testing.T, c *gl.GraphLinkClient) int {
	t.Helper()
	video, _ := must(c.Queries.CachedAttachments(ctx(t))).CachedAttachments[1].(gl.Video)
	return video.Seconds
}

func TestCachedListIsServedOnceAndRefetchedAfterEviction(t *testing.T) {
	c := newClient(t)
	expectNames(t, typeNames(must(c.Queries.CachedAttachments(ctx(t))).CachedAttachments), "Photo", "Video", "Document")
	before := cachedListVideoSeconds(t, c)
	expectEqual(t, cachedListVideoSeconds(t, c), before, "served from the cache")
	must(c.Mutations.EvictAttachments(ctx(t)))
	if cachedListVideoSeconds(t, c) == before {
		t.Fatal("the evicted tag must fetch the list again")
	}
}

func TestErrorOnAListOfUnionsFailsAndAGoodCallStillWorks(t *testing.T) {
	c := newClient(t)
	if _, err := c.Queries.FailingAttachments(ctx(t), true); err == nil {
		t.Fatal("expected an error")
	}
	expectEqual(t, len(must(c.Queries.FailingAttachments(ctx(t), false)).FailingAttachments), 3, "size")
}

func TestMutationReturningAListOfUnions(t *testing.T) {
	c := newClient(t)
	expectNames(t, typeNames(must(c.Mutations.BulkAttachments(ctx(t), 5)).BulkAttachments), "Photo", "Video", "Document", "Photo", "Video")
	expectEqual(t, len(must(c.Mutations.BulkAttachments(ctx(t), 0)).BulkAttachments), 0, "empty")
}

func TestMutationReturningAListOfAnInterface(t *testing.T) {
	c := newClient(t)
	expectNames(t, typeNames(must(c.Mutations.BulkEntities(ctx(t))).BulkEntities), "Article", "Comment", "Article")
}

func TestSubscriptionEmittingListsOfUnions(t *testing.T) {
	c := clientOnNewWs(t)
	events := c.Subscriptions.AttachmentsBatch(subscriptionContext(t))
	expectNames(t, typeNames(firstEvent(t, events).Data.AttachmentsBatch), "Photo", "Video", "Document")
	expectNames(t, typeNames(firstEvent(t, events).Data.AttachmentsBatch), "Document")
}

func TestSubscriptionEmittingAListOfAnInterface(t *testing.T) {
	c := clientOnNewWs(t)
	events := c.Subscriptions.EntityBatch(subscriptionContext(t))
	expectNames(t, typeNames(firstEvent(t, events).Data.EntityBatch), "Article", "Comment")
}

// ── @oneOf inputs with richer members ───────────────────────────────────────

func describePick(t *testing.T, pick gl.Pick) string {
	t.Helper()
	return must(newClient(t).Queries.DescribePick(ctx(t), pick)).DescribePick
}

func TestOneOfWithAnInputObject(t *testing.T) {
	inner := gl.InnerInput{N: ptr(5), Label: ptr("x"), Tags: []string{"t"}}
	expectEqual(t, describePick(t, gl.Pick{Inner: &inner}), "{inner={label=x, n=5, tags=[t]}}", "inner")
}

func TestOneOfWithAnEnum(t *testing.T) {
	expectEqual(t, describePick(t, gl.Pick{Status: ptr(gl.UserStatusSuspended)}), "{status=SUSPENDED}", "status")
}

func TestOneOfWithAListIncludingAnEmptyOne(t *testing.T) {
	expectEqual(t, describePick(t, gl.Pick{Ids: []int{1, 2}}), "{ids=[1, 2]}", "ids")
	expectEqual(t, describePick(t, gl.Pick{Ids: []int{}}), "{ids=[]}", "empty ids")
}

func TestOneOfWithAnotherOneOf(t *testing.T) {
	expectEqual(t, describePick(t, gl.Pick{Pet: &gl.Pet{Cat: ptr("Tom")}}), "{pet={cat=Tom}}", "pet")
}

func TestOneOfNestedInItself(t *testing.T) {
	deep := gl.Pick{Child: &gl.Pick{Child: &gl.Pick{Pet: &gl.Pet{Dog: ptr(3)}}}}
	expectEqual(t, describePick(t, deep), "{child={child={pet={dog=3}}}}", "deep")
}

func TestListOfOneOfInputsInsideARegularInput(t *testing.T) {
	c := newClient(t)
	pets := []gl.Pet{{Cat: ptr("a")}, {Dog: ptr(2)}}
	both := must(c.Queries.DescribeBasket(ctx(t), gl.Basket{Pets: pets, Lead: &gl.Pet{Dog: ptr(3)}})).DescribeBasket
	expectEqual(t, both, "{lead={dog=3}, pets=[{cat=a}, {dog=2}]}", "with lead")
	expectEqual(t, must(c.Queries.DescribeBasket(ctx(t), gl.Basket{Pets: pets})).DescribeBasket, "{pets=[{cat=a}, {dog=2}]}", "without lead")
	expectEqual(t, must(c.Queries.DescribeBasket(ctx(t), gl.Basket{Pets: []gl.Pet{}})).DescribeBasket, "{pets=[]}", "no pets")
}
