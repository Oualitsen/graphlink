package tests

import (
	"strings"
	"testing"

	"graphlink.dev/resttests/generated"
)

func kinds[T any](values []T) []string {
	out := make([]string, len(values))
	for i, v := range values {
		switch any(v).(type) {
		case generated.Dog:
			out[i] = "Dog"
		case generated.Cat:
			out[i] = "Cat"
		case generated.Product:
			out[i] = "Product"
		case generated.Owner:
			out[i] = "Owner"
		case nil:
			out[i] = "nil"
		default:
			out[i] = "other"
		}
	}
	return out
}

func failsNaming(t *testing.T, err error, parts ...string) {
	t.Helper()
	if err == nil {
		t.Fatal("expected an error")
	}
	for _, part := range parts {
		isTrue(t, strings.Contains(err.Error(), part), "error "+err.Error()+" does not name "+part)
	}
}

func TestNestedInterfaceAndUnionFieldsInsideAnObject(t *testing.T) {
	ctx, client := setup(t)
	kennel := must(client.Queries.Kennel(ctx))
	dog, isDog := kennel.Resident.(generated.Dog)
	isTrue(t, isDog && dog.Barks, "resident is a barking Dog")
	product, isProduct := kennel.Hit.(generated.Product)
	isTrue(t, isProduct, "hit is a Product")
	eq(t, product.Name, "Pen")
}

func TestNestedListsOfInterfacesAndUnions(t *testing.T) {
	ctx, client := setup(t)
	kennel := must(client.Queries.Kennel(ctx))
	eq(t, kinds(kennel.Featured), []string{"Dog", "Cat"})
	eq(t, kennel.Featured[1].(generated.Cat).Lives, 9)
	eq(t, kinds(kennel.Hits), []string{"Product", "Owner"})
}

func TestNestedNullElementsInAListOfInterfaces(t *testing.T) {
	ctx, client := setup(t)
	mixed := must(client.Queries.Kennel(ctx)).Mixed
	eq(t, kinds(mixed), []string{"Dog", "nil", "Cat"})
}

func TestNestedNullPolymorphicFields(t *testing.T) {
	ctx, client := setup(t)
	empty := must(client.Queries.Shelter(ctx)).Kennels[1]
	isTrue(t, empty.Resident == nil, "resident is nil")
	eq(t, len(empty.Featured), 0)
	isTrue(t, empty.Mixed == nil, "mixed is nil")
	isTrue(t, empty.Hit == nil, "hit is nil")
	isTrue(t, empty.Hits == nil, "hits is nil")
}

func TestNestedTwoLevelsDeep(t *testing.T) {
	ctx, client := setup(t)
	shelter := must(client.Queries.Shelter(ctx))
	eq(t, len(shelter.Kennels), 2)
	_, isDog := shelter.Kennels[0].Resident.(generated.Dog)
	isTrue(t, isDog, "first resident is a Dog")
	eq(t, shelter.Kennels[0].Featured[1].GetName(), "Tom")
}

func TestResultNullableElementsKeepNil(t *testing.T) {
	ctx, client := setup(t)
	eq(t, kinds(must(client.Queries.PetsNullable(ctx))), []string{"Dog", "nil", "Cat"})
}

func TestResultOptionalListDecodesAJSONNullAsNil(t *testing.T) {
	ctx, client := setup(t)
	isTrue(t, must(client.Queries.PetsOptional(ctx)) == nil, "nil list")
}

func TestResultThroughResponsePath(t *testing.T) {
	ctx, client := setup(t)
	eq(t, kinds(must(client.Queries.PetsWrapped(ctx))), []string{"Dog", "Cat"})
}

func TestResultFromAMutation(t *testing.T) {
	ctx, client := setup(t)
	pet := must(client.Mutations.AdoptPet(ctx, "c9"))
	_, isCat := pet.(generated.Cat)
	isTrue(t, isCat, "adopted pet is a Cat")
	eq(t, pet.GetId(), "c9")
	eq(t, pet.GetName(), "Adopted")
}

func TestResultFromACachedOperation(t *testing.T) {
	ctx, client := setup(t)
	first := must(client.Queries.CachedPet(ctx, "d7"))
	second := must(client.Queries.CachedPet(ctx, "d7"))
	_, isDog := first.(generated.Dog)
	isTrue(t, isDog, "cached pet is a Dog")
	eq(t, first.GetName(), "Rex1")
	eq(t, second.GetName(), "Rex1")
	eq(t, must(client.Queries.CachedPet(ctx, "d8")).GetName(), "Rex1")
}

func TestPayloadDiscriminatorKeyAbsent(t *testing.T) {
	ctx, client := setup(t)
	_, err := client.Queries.PetNoKind(ctx)
	failsNaming(t, err, "Pet", "kind")
}

func TestPayloadDiscriminatorNull(t *testing.T) {
	ctx, client := setup(t)
	_, err := client.Queries.PetNullKind(ctx)
	failsNaming(t, err, "Pet", "kind")
}

func TestPayloadUnknownKeysInsideAMemberAreIgnored(t *testing.T) {
	ctx, client := setup(t)
	pet := must(client.Queries.PetExtraKeys(ctx))
	_, isDog := pet.(generated.Dog)
	isTrue(t, isDog, "pet is a Dog")
	eq(t, pet.GetName(), "Rex")
}

func TestPayloadAMemberMissingARequiredFieldNamesTheField(t *testing.T) {
	ctx, client := setup(t)
	_, err := client.Queries.PetMissingField(ctx)
	failsNaming(t, err, "barks")
}
