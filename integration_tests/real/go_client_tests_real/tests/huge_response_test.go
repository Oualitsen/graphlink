package tests

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"
)

func TestATenMegabyteResponseIsDecodedWithoutLoss(t *testing.T) {
	raw, err := os.ReadFile("../../fault_server/huge_case.json")
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		Users int `json:"users"`
	}
	if err := json.Unmarshal(raw, &spec); err != nil {
		t.Fatal(err)
	}
	faultPost(t, "/_reset")
	faultPost(t, "/_arm?fault=huge-users")
	client := newClientOn(t, faultPort)

	started := time.Now()
	response := must(client.Queries.FetchBigUsers(ctx(t), spec.Users))
	elapsed := time.Since(started)

	users := response.BigUsers
	last := spec.Users - 1
	if len(users) != spec.Users {
		t.Fatalf("got %d users, want %d", len(users), spec.Users)
	}
	if users[0].Id != "user-0" {
		t.Fatalf("first id %q", users[0].Id)
	}
	if want := fmt.Sprintf("User %d Ünï 日本", last); users[last].Name != want {
		t.Fatalf("last name %q, want %q", users[last].Name, want)
	}
	if want := fmt.Sprintf("user-%d@example.com", last); users[last].Email != want {
		t.Fatalf("last email %q, want %q", users[last].Email, want)
	}
	if users[1].Status != "INACTIVE" {
		t.Fatalf("status %q", users[1].Status)
	}
	if tags := users[spec.Users/2].Tags; len(tags) != 2 || tags[0] != "alpha" || tags[1] != "beta" {
		t.Fatalf("tags %v", tags)
	}
	if users[0].Address.Zip != nil {
		t.Fatalf("zip %v", *users[0].Address.Zip)
	}
	if elapsed > 30*time.Second {
		t.Fatalf("decoding took %s", elapsed)
	}

	faultPost(t, "/_arm?fault=huge-users")
	if again := must(client.Queries.FetchBigUsers(ctx(t), spec.Users)); len(again.BigUsers) != spec.Users {
		t.Fatalf("second call got %d users", len(again.BigUsers))
	}
}
