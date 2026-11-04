package tests

import (
	"strings"
	"testing"

	"graphlink.dev/resttests/generated"
)

func TestLenientNullAndMissingFieldsDecodeAsNil(t *testing.T) {
	ctx, client := setup(t)
	product := must(client.Queries.LenientProduct(ctx))
	eq(t, *product.Id, "p1")
	isTrue(t, product.Name == nil, "name is nil")
	isTrue(t, product.Price == nil, "price is nil")
	isTrue(t, product.Tags == nil, "tags is nil")
}

func TestLenientNestedObjectsAreLenientToo(t *testing.T) {
	ctx, client := setup(t)
	related := must(client.Queries.LenientProduct(ctx)).Related
	eq(t, len(related), 2)
	eq(t, *related[0].Id, "p2")
	isTrue(t, related[0].Name == nil, "nested name is nil")
	isTrue(t, related[0].Related == nil, "nested related is nil")
	eq(t, *related[1].Name, "Three")
	eq(t, *related[1].Price, 3.5)
	isTrue(t, related[1].Related == nil, "explicit null related is nil")
}

func TestLenientListsOfObjectsDecode(t *testing.T) {
	ctx, client := setup(t)
	products := must(client.Queries.LenientProducts(ctx))
	eq(t, len(products), 2)
	isTrue(t, products[0].Name == nil, "first name is nil")
	eq(t, *products[1].Name, "B")
}

func TestLenientEmptyBodyIsStillNilBecauseTheSchemaSaysSo(t *testing.T) {
	ctx, client := setup(t)
	isTrue(t, must(client.Queries.LenientNothing(ctx)) == nil, "204 is nil")
}

func TestStrictTwinStillFailsOnTheSamePayload(t *testing.T) {
	ctx, client := setup(t)
	_, err := client.Queries.StrictProduct(ctx)
	isTrue(t, err != nil && strings.Contains(err.Error(), "Product.name is missing or null in the response"), "named decode error")
	_, err = client.Queries.StrictPets(ctx)
	isTrue(t, err != nil && strings.Contains(err.Error(), "is missing or null in the response"), "interface members stay strict")
}

func TestLenientInterfacesDecodeThroughTheirDiscriminatorWithMissingFields(t *testing.T) {
	ctx, client := setup(t)
	pets := must(client.Queries.LenientPets(ctx))
	eq(t, len(pets), 3)

	first, isDog := pets[0].(generated.DogRest)
	isTrue(t, isDog, "first pet is a DogRest")
	eq(t, *first.Id, "d1")
	isTrue(t, first.Name == nil && first.Barks == nil, "missing name and barks are nil")

	second, isCat := pets[1].(generated.CatRest)
	isTrue(t, isCat, "second pet is a CatRest")
	eq(t, *second.Id, "c1")
	isTrue(t, second.Name == nil && second.Lives == nil, "null name and missing lives are nil")

	third, isDog := pets[2].(generated.DogRest)
	isTrue(t, isDog, "third pet is a DogRest")
	isTrue(t, third.Id == nil, "missing id is nil")
	eq(t, *third.Name, "Rex")
	eq(t, *third.Barks, true)
}

func TestLenientUnionsDecodeThroughTheirDiscriminator(t *testing.T) {
	ctx, client := setup(t)
	hits := must(client.Queries.LenientHits(ctx))
	product, isProduct := hits[0].(generated.ProductRest)
	isTrue(t, isProduct, "first hit is a ProductRest")
	eq(t, *product.Id, "p1")
	owner, isOwner := hits[1].(generated.OwnerRest)
	isTrue(t, isOwner, "second hit is an OwnerRest")
	eq(t, *owner.Id, "o1")
	isTrue(t, owner.Name == nil, "missing owner name is nil")
}

func TestLenientCachedResultIsStoredAndDecodedTheSameWay(t *testing.T) {
	ctx, _ := setup(t)
	cached := newClient(t, clientOptions{store: generated.NewInMemoryGraphLinkCacheStore()})
	first := must(cached.Queries.LenientCached(ctx))
	second := must(cached.Queries.LenientCached(ctx))
	isTrue(t, first.Name == nil && second.Name == nil, "name stays nil")
	eq(t, len(second.Related), len(first.Related))
	eq(t, *second.Related[1].Name, "Three")
}
