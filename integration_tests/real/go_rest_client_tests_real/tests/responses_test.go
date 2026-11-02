package tests

import (
	"strings"
	"testing"

	"graphlink.dev/resttests/generated"
)

func TestStatusHandling(t *testing.T) {
	ctx, client := setup(t)
	ok := must(client.Queries.Status(ctx, 200))
	eq(t, ok.Name, "Pen")
	eq(t, must(client.Queries.Status(ctx, 201)).Id, "p1")

	none := must(client.Queries.Status(ctx, 204))
	isTrue(t, none == nil, "204 is nil when nullable")
	_, err := client.Queries.StatusNonNull(ctx, 204)
	isTrue(t, err != nil && strings.Contains(err.Error(), "Empty REST response"), "204 is an error when non-null")

	for _, code := range []int{400, 401, 403, 404, 409, 422, 500, 502, 503} {
		_, err := client.Queries.Status(ctx, code)
		failure := restError(t, err)
		eq(t, failure.Status, code)
		isTrue(t, strings.Contains(failure.Body, "status "+string(rune('0'+code/100))), "body is kept")
		eq(t, failure.Headers["x-reason"], "reason-"+itoa(code))
	}
	_, err = client.Queries.Status(ctx, 418)
	isTrue(t, strings.Contains(err.Error(), "418"), "error prints its status")
	eq(t, must(client.Queries.Status(ctx, 200)).Id, "p1")
}

func itoa(n int) string {
	digits := ""
	for n > 0 {
		digits = string(rune('0'+n%10)) + digits
		n /= 10
	}
	return digits
}

func TestEmptyBodiesAndValueKinds(t *testing.T) {
	ctx, client := setup(t)
	blank := must(client.Queries.Blank(ctx))
	isTrue(t, blank == nil, "empty 200 is nil when nullable")
	_, err := client.Queries.BlankNonNull(ctx)
	isTrue(t, err != nil && strings.Contains(err.Error(), "Empty REST response"), "empty 200 is an error when non-null")
	nc := must(client.Queries.NoContent(ctx))
	isTrue(t, nc == nil, "204 is nil")
	text := must(client.Queries.TextOptional(ctx))
	isTrue(t, text == nil, "204 text is nil")
	jn := must(client.Queries.JsonNull(ctx))
	isTrue(t, jn == nil, "JSON null is nil")

	eq(t, must(client.Queries.Count(ctx)), 7)
	eq(t, must(client.Queries.Flag(ctx)), true)
	eq(t, must(client.Queries.Text(ctx)), "héllo ✓")
	eq(t, must(client.Queries.Deep(ctx)), []int{1, 2, 3})
	wrapped := must(client.Queries.Wrapped(ctx))
	eq(t, []string{wrapped[0].Id, wrapped[1].Id}, []string{"p1", "p2"})

	u := must(client.Queries.Unicode(ctx))
	eq(t, u.Name, "é漢😀 \"quoted\"")
	eq(t, u.Tags, []string{"ß"})
	extra := must(client.Queries.ExtraKeys(ctx))
	eq(t, extra.Id, "x")
	isTrue(t, extra.Tags == nil, "null list stays nil")

	_, err = client.Queries.MissingField(ctx)
	isTrue(t, err != nil && strings.Contains(err.Error(), "Product.name is missing or null in the response"), "named decode error")

	p := must(client.Queries.Product(ctx, "p1"))
	eq(t, *p.Status, generated.StatusActive)
	eq(t, len(p.Related), 1)
	eq(t, p.Related[0].Name, "Book")
	isTrue(t, p.Related[0].Related == nil, "cycle ends")
}

func TestPolymorphism(t *testing.T) {
	ctx, client := setup(t)
	pets := must(client.Queries.Pets(ctx))
	dog, isDog := pets[0].(generated.Dog)
	isTrue(t, isDog && dog.Barks, "first pet is a barking Dog")
	cat, isCat := pets[1].(generated.Cat)
	isTrue(t, isCat && cat.Lives == 9, "second pet is a Cat")

	pet := must(client.Queries.Pet(ctx, "c1"))
	_, isCat = pet.(generated.Cat)
	isTrue(t, isCat, "single interface value")
	eq(t, pet.GetName(), "Tom")

	_, err := client.Queries.PetsUnknown(ctx)
	isTrue(t, err != nil && strings.Contains(err.Error(), "Pet") && strings.Contains(err.Error(), "bird"), "unknown discriminator")

	hits := must(client.Queries.Hits(ctx))
	_, isProduct := hits[0].(generated.Product)
	_, isOwner := hits[1].(generated.Owner)
	isTrue(t, isProduct && isOwner, "union decodes through its discriminator map")
}

func TestMixedClientAndEdgeCases(t *testing.T) {
	ctx, client := setup(t)
	eq(t, must(client.Queries.GetCount(ctx)).GetCount, 19)
	eq(t, must(client.Queries.Count(ctx)), 7)

	gz := must(client.Queries.Gzipped(ctx))
	eq(t, []string{gz[0].Id, gz[1].Id}, []string{"p1", "p2"})
	eq(t, must(client.Queries.Redirected(ctx)), 7)
	items := must(client.Queries.Big(ctx, 50000))
	eq(t, len(items), 50000)
	eq(t, items[len(items)-1].Name, "big-49999")

	_, err := client.Queries.InvalidJson(ctx)
	notRest(t, err)
	_, err = client.Queries.HtmlError(ctx)
	failure := restError(t, err)
	eq(t, failure.Status, 500)
	isTrue(t, strings.Contains(failure.Body, "Internal Server Error"), "text body kept")
	isTrue(t, strings.HasPrefix(failure.Headers["content-type"], "text/html"), "headers kept")
}
