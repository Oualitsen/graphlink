package tests

import (
	"errors"
	"reflect"
	"sort"
	"testing"
)

func setup(t *testing.T) (*ApqServer, func()) {
	t.Helper()
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	server.RespondTo("persistedShortQuery", object{"listUsers": list{}})
	server.RespondTo("persistedLongMutation", object{"createUser": userAliceJson})
	return server, func() {}
}

func TestLongQueryAsksWithAGetFirstAndRegistersWithAPost(t *testing.T) {
	server, _ := setup(t)
	must(newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"))
	if !reflect.DeepEqual(server.Methods, []string{"GET", "POST"}) || !IsHashOnly(server.Requests[0]) || !has(server.Requests[1], "query") {
		t.Fatalf("methods=%v requests=%v", server.Methods, server.Requests)
	}
}

func TestSingleGetOnceTheServerKnowsTheQuery(t *testing.T) {
	server, _ := setup(t)
	client := newClient(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	server.ClearRecords()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if !reflect.DeepEqual(server.Methods, []string{"GET"}) {
		t.Fatalf("methods: %v", server.Methods)
	}
}

func TestGetAdapterReceivesTheHashOnlyPayload(t *testing.T) {
	server, _ := setup(t)
	must(newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"))
	var keys []string
	for key := range server.Requests[0] {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	if !reflect.DeepEqual(keys, []string{"extensions", "operationName", "variables"}) {
		t.Fatalf("keys: %v", keys)
	}
}

func TestShortQueryAndMutationNeverUseGet(t *testing.T) {
	server, _ := setup(t)
	client := newClient(t, server)
	must(client.Queries.PersistedShortQuery(newContext(t)))
	if !reflect.DeepEqual(server.Methods, []string{"POST"}) {
		t.Fatalf("short query methods: %v", server.Methods)
	}
	server.ClearRecords()
	must(client.Mutations.PersistedLongMutation(newContext(t), newInput()))
	if !reflect.DeepEqual(server.Methods, []string{"POST", "POST"}) || !IsHashOnly(server.Requests[0]) {
		t.Fatalf("mutation methods: %v", server.Methods)
	}
}

func TestServerThatRefusesGet(t *testing.T) {
	server, _ := setup(t)
	server.GetSupported = false
	client := newClient(t, server)
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || !reflect.DeepEqual(server.Methods, []string{"GET", "POST", "POST"}) {
		t.Fatalf("methods: %v", server.Methods)
	}
	if len(server.Requests) != 2 || !IsHashOnly(server.Requests[0]) || !has(server.Requests[1], "query") {
		t.Fatalf("requests: %v", server.Requests)
	}
	server.ClearRecords()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if !reflect.DeepEqual(server.Methods, []string{"POST"}) {
		t.Fatalf("the client must stop trying GET: %v", server.Methods)
	}
}

func TestServerWithoutApqAnswersTheGetWithARefusal(t *testing.T) {
	server, _ := setup(t)
	server.Supported = false
	must(newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"))
	if !reflect.DeepEqual(server.Methods, []string{"GET", "POST"}) || !has(server.Requests[1], "query") || has(server.Requests[1], "extensions") {
		t.Fatalf("methods=%v requests=%v", server.Methods, server.Requests)
	}
}

func TestOtherGetFailuresPropagateWithNoPost(t *testing.T) {
	server, _ := setup(t)
	server.GetFailWith = errors.New("network down")
	if _, err := newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"); err == nil || err.Error() != "network down" {
		t.Fatalf("err: %v", err)
	}
	if !reflect.DeepEqual(server.Methods, []string{"GET"}) {
		t.Fatalf("methods: %v", server.Methods)
	}
}
