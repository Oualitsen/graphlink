package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"

	gl "graphlink.dev/persistedreal/generated"
)

const port = 9997

func control(t *testing.T, method, path string) map[string]any {
	t.Helper()
	request, err := http.NewRequest(method, "http://localhost:9997/test/apq"+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("control %s %s: %v (%s)", method, path, err, body)
	}
	return decoded
}

func stats(t *testing.T) map[string]float64 {
	t.Helper()
	result := map[string]float64{}
	for key, value := range control(t, "GET", "") {
		if number, ok := value.(float64); ok {
			result[key] = number
		}
	}
	return result
}

func expectStats(t *testing.T, want map[string]float64) {
	t.Helper()
	got := stats(t)
	for key, value := range want {
		if got[key] != value {
			t.Fatalf("stats[%s] = %v, want %v (all: %v)", key, got[key], value, got)
		}
	}
}

func newClient(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{URL: "http://localhost:9997/graphql", WsURL: "ws://localhost:9997/graphql"})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	return c
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func reset(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	control(t, "POST", "/reset")
	return newClient(t)
}

func newUser() gl.CreateUserInput {
	return gl.CreateUserInput{
		Name: "Persisted Pat", Email: "pat@test.com", Status: gl.UserStatusActive,
		Address: gl.AddressInput{Street: "s", City: "c", Country: "x"},
	}
}

func TestLongQueryIsRegisteredOnTheFirstCall(t *testing.T) {
	client := reset(t)
	res := must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" {
		t.Fatalf("name: %s", res.GetUser.Name)
	}
	expectStats(t, map[string]float64{"misses": 1, "registrations": 1, "stored": 1, "gets": 1})
}

func TestLongQueryIsASingleGetHitOnceRegistered(t *testing.T) {
	client := reset(t)
	must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	res := must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" {
		t.Fatalf("name: %s", res.GetUser.Name)
	}
	expectStats(t, map[string]float64{"hits": 1, "registrations": 1, "gets": 2})
}

func TestAFreshClientReusesWhatTheServerStored(t *testing.T) {
	client := reset(t)
	must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	res := must(newClient(t).Queries.PersistedLongQuery(ctx(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" {
		t.Fatalf("name: %s", res.GetUser.Name)
	}
	expectStats(t, map[string]float64{"hits": 1, "registrations": 1})
}

func TestRegisteredAgainAfterTheServerEvicts(t *testing.T) {
	client := reset(t)
	must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	control(t, "POST", "/evict")
	res := must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" {
		t.Fatalf("name: %s", res.GetUser.Name)
	}
	expectStats(t, map[string]float64{"registrations": 2, "stored": 1})
}

func TestStillWorksWhenTheServerDoesNotSupportPersistedQueries(t *testing.T) {
	client := reset(t)
	control(t, "POST", "/supported/false")
	first := must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	second := must(client.Queries.PersistedLongQuery(ctx(t), "user-1"))
	if first.GetUser.Name != "Alice Smith" || second.GetUser.Name != "Alice Smith" {
		t.Fatalf("names: %s %s", first.GetUser.Name, second.GetUser.Name)
	}
	expectStats(t, map[string]float64{"stored": 0, "gets": 1})
}

func TestLongMutationIsRegisteredAndSentOverPostNeverGet(t *testing.T) {
	client := reset(t)
	res := must(client.Mutations.PersistedLongMutation(ctx(t), newUser()))
	if res.CreateUser.Name != "Persisted Pat" {
		t.Fatalf("name: %s", res.CreateUser.Name)
	}
	expectStats(t, map[string]float64{"registrations": 1, "gets": 0})
}

func TestLongMutationIsAHashOnlyPostOnceRegistered(t *testing.T) {
	client := reset(t)
	must(client.Mutations.PersistedLongMutation(ctx(t), newUser()))
	res := must(client.Mutations.PersistedLongMutation(ctx(t), newUser()))
	if res.CreateUser.Email != "pat@test.com" {
		t.Fatalf("email: %s", res.CreateUser.Email)
	}
	expectStats(t, map[string]float64{"hits": 1, "registrations": 1, "gets": 0})
}

func TestShortQueryDoesNotUsePersistedQueries(t *testing.T) {
	client := reset(t)
	res := must(client.Queries.PersistedShortQuery(ctx(t)))
	if len(res.ListUsers) == 0 {
		t.Fatal("expected users")
	}
	expectStats(t, map[string]float64{"hits": 0, "misses": 0, "registrations": 0, "gets": 0})
}
