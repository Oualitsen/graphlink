package tests

import (
	"testing"

	gl "graphlink.dev/mocktests/generated"
)

func TestCreateUserResponseDeserialization(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("createUser", object{"createUser": userAliceJson})
	u := must(h.client.Mutations.CreateUser(h.ctx, minimalInput())).CreateUser
	expectEqual(t, u.Id, "user-1", "id")
	expectEqual(t, u.Name, "Alice Smith", "name")
	expectEqual(t, u.Email, "alice@test.com", "email")
	expectEqual(t, u.Status, gl.UserStatusActive, "status")
	if u.Priority == nil || *u.Priority != gl.PriorityHigh {
		t.Fatalf("priority: %v", u.Priority)
	}
	expectEqual(t, u.Address.Street, "123 Main St", "street")
	expectEqual(t, u.Address.City, "Springfield", "city")
	expectEqual(t, u.Address.Country, "US", "country")
	expectEqual(t, *u.Address.Zip, "12345", "zip")
	if u.BillingAddress != nil {
		t.Fatal("billingAddress should be nil")
	}
	if len(u.Tags) != 2 || len(u.Scores) != 3 {
		t.Fatalf("tags=%v scores=%v", u.Tags, u.Scores)
	}
	expectEqual(t, h.adapter.LastCall().OperationName, "createUser", "operation name")
	if h.adapter.LastCall().Variables["input"] == nil {
		t.Fatal("input variable missing")
	}
}

func TestCreateUserResponseWithNullableFieldsPopulated(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("createUser", object{"createUser": userBobJson})
	u := must(h.client.Mutations.CreateUser(h.ctx, minimalInput())).CreateUser
	expectEqual(t, u.Status, gl.UserStatusInactive, "status")
	if u.Priority != nil || u.Scores != nil || len(u.Tags) != 0 {
		t.Fatalf("priority=%v scores=%v tags=%v", u.Priority, u.Scores, u.Tags)
	}
	expectEqual(t, u.BillingAddress.City, "Capital City", "billing city")
}

func TestDeleteUser(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("deleteUser", object{"deleteUser": true})
	if !must(h.client.Mutations.DeleteUser(h.ctx, "user-99")).DeleteUser {
		t.Fatal("expected true")
	}
	expectEqual(t, h.adapter.LastCall().Variables["id"].(string), "user-99", "id variable")
	expectEqual(t, h.adapter.LastCall().OperationName, "deleteUser", "operation name")
	h.adapter.RegisterData("deleteUser", object{"deleteUser": false})
	if must(h.client.Mutations.DeleteUser(h.ctx, "user-1")).DeleteUser {
		t.Fatal("expected false")
	}
}

func TestUpdateUser(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("updateUser", object{"updateUser": userAliceJson})
	name := "Alice Smith"
	u := must(h.client.Mutations.UpdateUser(h.ctx, "user-42", gl.UpdateUserInput{Name: &name})).UpdateUser
	expectEqual(t, u.Id, "user-1", "id")
	expectEqual(t, u.Name, "Alice Smith", "name")
	expectEqual(t, u.Status, gl.UserStatusActive, "status")
	expectEqual(t, u.Address.Street, "123 Main St", "street")
	call := h.adapter.LastCall()
	expectEqual(t, call.Variables["id"].(string), "user-42", "id variable")
	expectEqual(t, call.OperationName, "updateUser", "operation name")
	if call.Variables["input"] == nil {
		t.Fatal("input variable missing")
	}
}

func sentInput(h *harness) map[string]any {
	return h.adapter.LastCall().Variables["input"].(map[string]any)
}

func TestCreateUserInputSerialization(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("createUser", object{"createUser": userAliceJson})
	zip := "12345"
	priority := gl.PriorityCritical
	input := gl.CreateUserInput{
		Name: "Alice Smith", Email: "alice@test.com", Status: gl.UserStatusSuspended, Priority: &priority,
		Address: gl.AddressInput{Street: "123 Main St", City: "Springfield", Country: "US", Zip: &zip},
		Tags:    []string{"admin", "beta"},
	}
	must(h.client.Mutations.CreateUser(h.ctx, input))
	sent := sentInput(h)
	expectEqual(t, sent["name"].(string), "Alice Smith", "name")
	expectEqual(t, sent["email"].(string), "alice@test.com", "email")
	expectEqual(t, sent["status"].(string), "SUSPENDED", "status")
	expectEqual(t, sent["priority"].(string), "CRITICAL", "priority")
	address := sent["address"].(map[string]any)
	expectEqual(t, address["street"].(string), "123 Main St", "street")
	expectEqual(t, address["zip"].(string), "12345", "zip")
	tags := sent["tags"].([]any)
	if len(tags) != 2 || tags[0] != "admin" || tags[1] != "beta" {
		t.Fatalf("tags: %v", tags)
	}
}

func TestOptionalInputFieldsAreNullWhenOmitted(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("createUser", object{"createUser": userAliceJson})
	must(h.client.Mutations.CreateUser(h.ctx, minimalInput()))
	sent := sentInput(h)
	if sent["priority"] != nil || sent["billingAddress"] != nil {
		t.Fatalf("optional fields should be null: %v", sent)
	}
	if sent["address"].(map[string]any)["zip"] != nil {
		t.Fatal("zip should be null")
	}
}

func TestEmptyTagsListIsSerializedAsEmptyList(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("createUser", object{"createUser": userAliceJson})
	input := minimalInput()
	input.Tags = []string{}
	must(h.client.Mutations.CreateUser(h.ctx, input))
	if tags := sentInput(h)["tags"].([]any); len(tags) != 0 {
		t.Fatalf("tags: %v", tags)
	}
}

func TestUpdateUserInputOnlyProvidedFieldsAreNonNull(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("updateUser", object{"updateUser": userAliceJson})
	name := "New Name"
	must(h.client.Mutations.UpdateUser(h.ctx, "user-1", gl.UpdateUserInput{Name: &name}))
	sent := sentInput(h)
	expectEqual(t, sent["name"].(string), "New Name", "name")
	if sent["email"] != nil || sent["status"] != nil {
		t.Fatalf("unset fields should be null: %v", sent)
	}
}
