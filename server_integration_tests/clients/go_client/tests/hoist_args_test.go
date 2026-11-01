package tests

import (
	"strings"
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

func TestManyRequiredHoistedArgsInputRenamedOnCollision(t *testing.T) {
	c := newClient(t)
	catalog := must(c.Queries.Catalog(ctx(t), gl.CatalogFieldArgs1{ProductsCategory: "books", ProductsLimit: 3, ProductsOffset: gl.Ptr(0)})).Catalog
	if len(catalog.Products) != 3 {
		t.Fatalf("got %d products", len(catalog.Products))
	}
	for _, p := range catalog.Products {
		if !strings.HasPrefix(p.Name, "books") {
			t.Fatalf("unexpected product %q", p.Name)
		}
	}
}

func TestAllOptionalHoistedArgsCanBeOmitted(t *testing.T) {
	c := newClient(t)
	if n := len(must(c.Queries.Feed(ctx(t))).Feed.Items); n != 10 {
		t.Fatalf("got %d items", n)
	}
}

func TestOptionalHoistedArgsCanBeSupplied(t *testing.T) {
	c := newClient(t)
	feed := must(c.Queries.Feed(ctx(t), gl.FeedOptions{FieldArgs: &gl.FeedFieldArgs{ItemsLimit: gl.Ptr(4), ItemsSort: gl.Ptr("z")}})).Feed
	if len(feed.Items) != 4 || !strings.HasPrefix(feed.Items[0].Name, "z") {
		t.Fatalf("unexpected feed: %+v", feed)
	}
}

func TestNestedDepthHoistingCollapsesIntoOneInput(t *testing.T) {
	c := newClient(t)
	store := must(c.Queries.Store(ctx(t), gl.StoreFieldArgs{ShelvesFloor: 2, ProductsLimit: 3})).Store
	if len(store.Shelves) != 2 || len(store.Shelves[0].Products) != 3 {
		t.Fatalf("unexpected store: %+v", store)
	}
}

func TestParamNameCollisionUsesFieldArgs1ForSyntheticArg(t *testing.T) {
	c := newClient(t)
	search := must(c.Queries.Search(ctx(t), "q", gl.SearchFieldArgs{HitsLimit: 3})).Search
	if search.Id != "q" || len(search.Hits) != 3 {
		t.Fatalf("unexpected search: %+v", search)
	}
}
