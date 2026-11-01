package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestInputFieldDefaultsAreApplied(t *testing.T) {
	c := newClient(t)
	input := gl.NewCreateWithDefaultsInput()
	input.Name = "test"
	res := must(c.Mutations.CreateWithDefaults(ctx(t), input)).CreateWithDefaults
	expectEqual(t, res.Name, "test", "name")
	if res.Role != gl.RoleUser || res.Age != 18 || !res.IsActive || res.Score != 4.5 || res.Nickname != "anonymous" {
		t.Fatalf("defaults: %+v", res)
	}
	if len(res.Tags) != 2 || *res.Tags[0] != "dart" || *res.Tags[1] != "graphql" {
		t.Fatalf("tags: %v", res.Tags)
	}
}

func TestExplicitValuesOverrideInputDefaults(t *testing.T) {
	c := newClient(t)
	input := gl.NewCreateWithDefaultsInput()
	input.Name = "override-test"
	input.Role = gl.Ptr(gl.RoleAdmin)
	input.Age = gl.Ptr(99)
	input.IsActive = gl.Ptr(false)
	input.Score = gl.Ptr(9.9)
	input.Nickname = gl.Ptr("custom")
	input.Tags = []*string{gl.Ptr("custom-tag")}
	res := must(c.Mutations.CreateWithDefaults(ctx(t), input)).CreateWithDefaults
	if res.Role != gl.RoleAdmin || res.Age != 99 || res.IsActive || res.Score != 9.9 || res.Nickname != "custom" {
		t.Fatalf("overrides: %+v", res)
	}
	if len(res.Tags) != 1 || *res.Tags[0] != "custom-tag" {
		t.Fatalf("tags: %v", res.Tags)
	}
}

func TestArgumentDefaults(t *testing.T) {
	c := newClient(t)
	if len(must(c.Queries.ListUsersWithDefaults(ctx(t))).ListUsersWithDefaults) == 0 {
		t.Fatal("expected users")
	}
	limited := must(c.Queries.ListUsersWithDefaults(ctx(t), gl.ListUsersWithDefaultsOptions{Limit: gl.Ptr(1)}))
	expectEqual(t, len(limited.ListUsersWithDefaults), 1, "limited users")
	admin := must(c.Queries.ListUsersWithDefaults(ctx(t), gl.ListUsersWithDefaultsOptions{Role: gl.Ptr(gl.RoleAdmin)}))
	if len(admin.ListUsersWithDefaults) == 0 {
		t.Fatal("expected admin users")
	}
}

func TestNestedObjectAndListDefaults(t *testing.T) {
	c := newClient(t)
	input := gl.NewNestedDefaultsInput()
	input.Name = "nested-test"
	res := must(c.Mutations.CreateWithNestedDefaults(ctx(t), input)).CreateWithNestedDefaults
	expectEqual(t, res.Name, "nested-test", "name")

	a := res.Address
	if a == nil || a.Street != "123 Main St" || a.City != "Springfield" || a.Country != "US" || *a.Zip != "12345" {
		t.Fatalf("address: %+v", a)
	}
	expectEqual(t, len(res.Contacts), 2, "contacts")
	if res.Contacts[0].Street != "456 Oak Ave" || res.Contacts[0].City != "Shelbyville" || res.Contacts[0].Zip != nil {
		t.Fatalf("contact 0: %+v", res.Contacts[0])
	}
	if res.Contacts[1].Street != "789 Pine Rd" || res.Contacts[1].City != "Capital City" || *res.Contacts[1].Zip != "99999" {
		t.Fatalf("contact 1: %+v", res.Contacts[1])
	}
	expectEqual(t, len(res.Matrix), 2, "matrix")
	first, second := res.Matrix[0][0], res.Matrix[1][0]
	if first.Street != "1st St" || first.City != "Paris" || first.Country != "FR" || *first.Zip != "75000" {
		t.Fatalf("matrix[0][0]: %+v", first)
	}
	if second.Street != "2nd St" || second.City != "Lyon" || second.Country != "FR" || *second.Zip != "69000" {
		t.Fatalf("matrix[1][0]: %+v", second)
	}
}

func TestExplicitValuesOverrideNestedDefaults(t *testing.T) {
	c := newClient(t)
	input := gl.NewNestedDefaultsInput()
	input.Name = "override-nested"
	input.Address = &gl.AddressInput{Street: "Custom St", City: "Custom City", Country: "XX"}
	input.Contacts = []*gl.AddressInput{{Street: "One", City: "Two", Country: "Three", Zip: gl.Ptr("44444")}}
	input.Matrix = [][]*gl.AddressInput{{{Street: "A", City: "B", Country: "C"}}}
	res := must(c.Mutations.CreateWithNestedDefaults(ctx(t), input)).CreateWithNestedDefaults
	if res.Address.Street != "Custom St" || res.Address.City != "Custom City" || res.Address.Country != "XX" || res.Address.Zip != nil {
		t.Fatalf("address: %+v", res.Address)
	}
	if len(res.Contacts) != 1 || res.Contacts[0].Street != "One" {
		t.Fatalf("contacts: %+v", res.Contacts)
	}
	if len(res.Matrix) != 1 || res.Matrix[0][0].Street != "A" {
		t.Fatalf("matrix: %+v", res.Matrix)
	}
}

func TestFieldArgumentDefaults(t *testing.T) {
	c := newClient(t)
	args := gl.NewGetDriverFieldArgs()
	args.LastUsedMillageOdometerKm = 200
	res := must(c.Queries.GetDriver(ctx(t), "driver-1", args)).GetDriver
	expectEqual(t, res.LastUsedMillage, 200, "millage")
	expectEqual(t, res.LastUsedFuel, 4, "fuel defaults to 4")

	args.LastUsedFuelLiters = 25
	args.LastUsedMillageOdometerKm = 500
	res = must(c.Queries.GetDriver(ctx(t), "driver-1", args)).GetDriver
	expectEqual(t, res.LastUsedMillage, 500, "millage")
	expectEqual(t, res.LastUsedFuel, 25, "explicit fuel")
}
