package tests

import (
	"errors"
	"strings"
	"testing"
)

func has(request object, key string) bool {
	_, ok := request[key]
	return ok
}

func TestLongQueryIsSentAsAHashFirstAndRegisteredByTheRetry(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client := newClient(t, server)
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || len(server.Requests) != 2 {
		t.Fatalf("name=%s requests=%d", res.GetUser.Name, len(server.Requests))
	}
	hashOnly := server.Requests[0]
	if has(hashOnly, "query") || hashOnly["operationName"] != "persistedLongQuery" || hashOnly["variables"].(object)["id"] != "user-1" {
		t.Fatalf("hash-only request: %v", hashOnly)
	}
	retry := server.Requests[1]
	if _, ok := retry["query"].(string); !ok || retry["variables"].(object)["id"] != "user-1" {
		t.Fatalf("retry request: %v", retry)
	}
}

func TestTheHashIsTheSha256OfTheQueryTheRetryCarries(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	must(newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"))
	retry := server.Requests[1]
	hash := extensionHash(retry)
	if hash["version"] != float64(1) || hash["sha256Hash"] != sha256Hex(retry["query"].(string)) {
		t.Fatalf("hash: %v", hash)
	}
	if extensionHash(server.Requests[0])["sha256Hash"] != hash["sha256Hash"] {
		t.Fatal("the first and the retry request must carry the same hash")
	}
}

func TestSingleRequestOnceTheServerKnowsTheQuery(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client := newClient(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	server.ClearRecords()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if len(server.Requests) != 1 || !IsHashOnly(server.Requests[0]) || server.Requests[0]["variables"].(object)["id"] != "user-2" {
		t.Fatalf("requests: %v", server.Requests)
	}
}

func TestRegisteredAgainAfterEviction(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client := newClient(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	server.Evict()
	server.ClearRecords()
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || len(server.Requests) != 2 || !IsHashOnly(server.Requests[0]) || !has(server.Requests[1], "query") {
		t.Fatalf("requests: %v", server.Requests)
	}
}

func TestServerThatReportsAMissingHashOnlyByItsCode(t *testing.T) {
	server := NewApqServer()
	server.NotFoundMessage = "Unknown query"
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	res := must(newClient(t, server).Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || len(server.Requests) != 2 || !has(server.Requests[1], "query") {
		t.Fatalf("requests: %v", server.Requests)
	}
}

func TestShortQueryIsSentInFullWithNoHash(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedShortQuery", object{"listUsers": list{}})
	must(newClient(t, server).Queries.PersistedShortQuery(newContext(t)))
	request := server.Requests[0]
	if len(server.Requests) != 1 || !strings.Contains(request["query"].(string), "listUsers") || has(request, "extensions") {
		t.Fatalf("request: %v", request)
	}
}

func TestLongMutationUsesTheSameFlow(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongMutation", object{"createUser": userAliceJson})
	res := must(newClient(t, server).Mutations.PersistedLongMutation(newContext(t), newInput()))
	if res.CreateUser.Name != "Alice Smith" || len(server.Requests) != 2 || !IsHashOnly(server.Requests[0]) || !has(server.Requests[1], "query") {
		t.Fatalf("requests: %v", server.Requests)
	}
}

func TestServerWithoutApq(t *testing.T) {
	server := NewApqServer()
	server.Supported = false
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client := newClient(t, server)
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || len(server.Requests) != 2 || !has(server.Requests[1], "query") || has(server.Requests[1], "extensions") {
		t.Fatalf("requests: %v", server.Requests)
	}
	server.ClearRecords()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if len(server.Requests) != 1 || !has(server.Requests[0], "query") || has(server.Requests[0], "extensions") {
		t.Fatalf("the client must stop asking about hashes: %v", server.Requests)
	}
}

func TestGraphQLErrorIsReturnedWithoutASecondRequest(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client := newClient(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	server.ClearRecords()
	server.RespondWithErrors("persistedLongQuery", object{"message": "boom"})
	if _, err := client.Queries.PersistedLongQuery(newContext(t), "user-1"); err == nil {
		t.Fatal("expected an error")
	}
	if len(server.Requests) != 1 {
		t.Fatalf("requests: %d", len(server.Requests))
	}
}

func TestTransportFailurePropagatesWithoutASecondRequest(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongMutation", object{"createUser": userAliceJson})
	server.FailWith = errors.New("timeout")
	_, err := newClient(t, server).Mutations.PersistedLongMutation(newContext(t), newInput())
	if err == nil || err.Error() != "timeout" {
		t.Fatalf("err: %v", err)
	}
	if len(server.Methods) != 1 || server.Methods[0] != "POST" {
		t.Fatalf("methods: %v", server.Methods)
	}
}

func TestCachedQueryHashesTheAssembledRequest(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("fetchCachedPair", object{"user": userAliceJson, "post": postJson})
	res := must(newClient(t, server).Queries.FetchCachedPair(newContext(t), "user-1", "post-1"))
	if res.User.Name != "Alice Smith" || len(server.Requests) != 2 {
		t.Fatalf("requests: %d", len(server.Requests))
	}
	retry := server.Requests[1]
	query := retry["query"].(string)
	if extensionHash(retry)["sha256Hash"] != sha256Hex(query) || !strings.Contains(query, "getCachedUser") {
		t.Fatalf("retry: %v", retry)
	}
}
