package tests

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sync"
	"testing"

	gl "graphlink.dev/persistedmock/generated"
)

type seenRequest struct {
	Method        string
	Query         map[string]string
	Authorization string
}

func startHttpServer(t *testing.T, server *ApqServer) (*gl.GraphLinkClient, func() []seenRequest, func()) {
	t.Helper()
	var mu sync.Mutex
	var seen []seenRequest
	hs := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query := map[string]string{}
		for key, values := range r.URL.Query() {
			query[key] = values[0]
		}
		mu.Lock()
		seen = append(seen, seenRequest{r.Method, query, r.Header.Get("Authorization")})
		mu.Unlock()
		var body string
		var err error
		if r.Method == "GET" {
			payload := object{"variables": object{}}
			if name, ok := query["operationName"]; ok {
				payload["operationName"] = name
			}
			if raw, ok := query["variables"]; ok {
				var variables object
				_ = json.Unmarshal([]byte(raw), &variables)
				payload["variables"] = variables
			}
			var extensions object
			_ = json.Unmarshal([]byte(query["extensions"]), &extensions)
			payload["extensions"] = extensions
			encoded, _ := json.Marshal(payload)
			body, err = server.Get(r.Context(), string(encoded))
		} else {
			raw, _ := io.ReadAll(r.Body)
			body, err = server.Call(r.Context(), string(raw))
		}
		var notSupported *gl.GraphLinkGetNotSupported
		if errors.As(err, &notSupported) {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(body))
	}))
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{
		URL:       hs.URL + "/graphql",
		WsAdapter: NoWebSocketAdapter{},
		HeadersProvider: func(ctx context.Context) (map[string]string, error) {
			return map[string]string{"Authorization": "Bearer token"}, nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	snapshot := func() []seenRequest {
		mu.Lock()
		defer mu.Unlock()
		return append([]seenRequest(nil), seen...)
	}
	clear := func() {
		mu.Lock()
		defer mu.Unlock()
		seen = nil
	}
	t.Cleanup(hs.Close)
	return client, snapshot, clear
}

func methodsOf(seen []seenRequest) []string {
	var methods []string
	for _, r := range seen {
		methods = append(methods, r.Method)
	}
	return methods
}

func TestColdLongQueryIsAGetWithTheHashThenAPostWithTheQuery(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client, seen, _ := startHttpServer(t, server)
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || !reflect.DeepEqual(methodsOf(seen()), []string{"GET", "POST"}) {
		t.Fatalf("methods: %v", methodsOf(seen()))
	}
}

func TestTheGetCarriesTheOperationItsVariablesAndTheHashInTheUrl(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client, seen, _ := startHttpServer(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	query := seen()[0].Query
	if len(query) != 3 || query["operationName"] != "persistedLongQuery" {
		t.Fatalf("query: %v", query)
	}
	var variables, extensions object
	_ = json.Unmarshal([]byte(query["variables"]), &variables)
	_ = json.Unmarshal([]byte(query["extensions"]), &extensions)
	if variables["id"] != "user-1" || extensions["persistedQuery"].(object)["version"] != float64(1) {
		t.Fatalf("variables=%v extensions=%v", variables, extensions)
	}
}

func TestWarmQueryIsASingleGet(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client, seen, clear := startHttpServer(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	clear()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if !reflect.DeepEqual(methodsOf(seen()), []string{"GET"}) {
		t.Fatalf("methods: %v", methodsOf(seen()))
	}
}

func TestHeadersProviderAppliesToTheGetAsWell(t *testing.T) {
	server := NewApqServer()
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client, seen, _ := startHttpServer(t, server)
	must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if seen()[0].Authorization != "Bearer token" {
		t.Fatalf("authorization: %q", seen()[0].Authorization)
	}
}

func TestA405OnGetSendsTheSameRequestAsAPostAndRemembersIt(t *testing.T) {
	server := NewApqServer()
	server.GetSupported = false
	server.RespondTo("persistedLongQuery", object{"getUser": userAliceJson})
	client, seen, clear := startHttpServer(t, server)
	res := must(client.Queries.PersistedLongQuery(newContext(t), "user-1"))
	if res.GetUser.Name != "Alice Smith" || !reflect.DeepEqual(methodsOf(seen()), []string{"GET", "POST", "POST"}) {
		t.Fatalf("methods: %v", methodsOf(seen()))
	}
	clear()
	must(client.Queries.PersistedLongQuery(newContext(t), "user-2"))
	if !reflect.DeepEqual(methodsOf(seen()), []string{"POST"}) {
		t.Fatalf("methods: %v", methodsOf(seen()))
	}
}
