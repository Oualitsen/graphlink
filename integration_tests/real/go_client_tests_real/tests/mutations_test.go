package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestCreateUserEchoesInput(t *testing.T) {
	c := newClient(t)
	u := must(c.Mutations.CreateUser(ctx(t), minimalInput())).CreateUser
	expectEqual(t, u.Name, "Alice Smith", "name")
	expectEqual(t, u.Email, "alice@test.com", "email")
	expectEqual(t, u.Status, gl.UserStatusActive, "status")
	expectEqual(t, u.Address.Street, "123 Main St", "street")
	expectEqual(t, u.Address.City, "Springfield", "city")
	if u.Priority != nil || u.Address.Zip != nil || u.BillingAddress != nil || len(u.Tags) != 0 {
		t.Fatalf("optional fields should be empty: %+v", u)
	}
}

func TestCreateUserInputSerialization(t *testing.T) {
	c := newClient(t)
	zip := "12345"
	priority := gl.PriorityHigh
	input := gl.CreateUserInput{
		Name: "Alice", Email: "test@example.com", Status: gl.UserStatusSuspended, Priority: &priority,
		Address: gl.AddressInput{Street: "123 Main St", City: "Springfield", Country: "US", Zip: &zip},
		Tags:    []string{"admin", "beta"},
	}
	u := must(c.Mutations.CreateUser(ctx(t), input)).CreateUser
	expectEqual(t, u.Email, "test@example.com", "email")
	expectEqual(t, u.Status, gl.UserStatusSuspended, "status")
	if u.Priority == nil || *u.Priority != gl.PriorityHigh {
		t.Fatalf("priority: %v", u.Priority)
	}
	expectEqual(t, *u.Address.Zip, "12345", "zip")
	if len(u.Tags) != 2 || u.Tags[0] != "admin" || u.Tags[1] != "beta" {
		t.Fatalf("tags: %v", u.Tags)
	}
	input.Tags = []string{}
	if tags := must(c.Mutations.CreateUser(ctx(t), input)).CreateUser.Tags; len(tags) != 0 {
		t.Fatalf("tags: %v", tags)
	}
}

func TestDeleteUser(t *testing.T) {
	c := newClient(t)
	if !must(c.Mutations.DeleteUser(ctx(t), "user-1")).DeleteUser {
		t.Fatal("expected true")
	}
}

func TestUpdateUser(t *testing.T) {
	c := newClient(t)
	name := "Updated Alice"
	u := must(c.Mutations.UpdateUser(ctx(t), "user-1", gl.UpdateUserInput{Name: &name})).UpdateUser
	expectEqual(t, u.Id, "user-1", "id")
	expectEqual(t, u.Name, "Updated Alice", "name")
	expectEqual(t, u.Email, "alice@test.com", "email is preserved")
	expectEqual(t, u.Address.Street, "123 Main St", "address is preserved")

	status := gl.UserStatusSuspended
	updated := must(c.Mutations.UpdateUser(ctx(t), "user-1", gl.UpdateUserInput{Status: &status})).UpdateUser
	expectEqual(t, updated.Status, gl.UserStatusSuspended, "status")

	active := gl.UserStatusActive
	other := must(c.Mutations.UpdateUser(ctx(t), "user-2", gl.UpdateUserInput{Status: &active})).UpdateUser
	expectEqual(t, other.Id, "user-2", "id")
	expectEqual(t, other.Status, gl.UserStatusActive, "status")
}
