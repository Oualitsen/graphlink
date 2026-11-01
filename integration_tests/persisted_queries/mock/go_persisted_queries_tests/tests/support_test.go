package tests

import (
	"context"
	"testing"
	"time"

	gl "graphlink.dev/persistedmock/generated"
)

type object = map[string]any
type list = []any

var userAliceJson = object{
	"id": "user-1", "name": "Alice Smith", "email": "alice@test.com", "status": "ACTIVE", "priority": "HIGH",
	"address":        object{"street": "123 Main St", "city": "Springfield", "country": "US", "zip": "12345"},
	"billingAddress": nil, "tags": list{"admin", "beta"}, "scores": list{10, 20, 30},
}

var postJson = object{
	"id": "post-1", "title": "Hello World", "body": "Post body text.", "author": userAliceJson,
	"coAuthor": nil, "viewCount": 128,
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func newContext(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	return c
}

func newClient(t *testing.T, server *ApqServer) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{
		Adapter:    server.Call,
		GetAdapter: server.Get,
		WsAdapter:  NoWebSocketAdapter{},
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func newInput() gl.CreateUserInput {
	return gl.CreateUserInput{
		Name: "Alice", Email: "a@test.com", Status: gl.UserStatusActive,
		Address: gl.AddressInput{Street: "s", City: "c", Country: "x"},
	}
}

func extensionHash(request object) object {
	return request["extensions"].(object)["persistedQuery"].(object)
}
