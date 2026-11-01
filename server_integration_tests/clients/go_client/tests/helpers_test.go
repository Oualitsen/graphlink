package tests

import (
	"context"
	"os"
	"testing"
	"time"

	gl "graphlink.dev/serverintegration/generated"
)

func port() string {
	if p := os.Getenv("SERVER_PORT"); p != "" {
		return p
	}
	return "9997"
}

func newClient(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{
		URL:   "http://localhost:" + port() + "/graphql",
		WsURL: "ws://localhost:" + port() + "/graphql",
	})
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

func firstEvent[T any](t *testing.T, events <-chan gl.GraphLinkEvent[T]) gl.GraphLinkEvent[T] {
	t.Helper()
	select {
	case event, ok := <-events:
		if !ok {
			t.Fatal("subscription closed before an event arrived")
		}
		return event
	case <-time.After(10 * time.Second):
		t.Fatal("timed out waiting for subscription event")
	}
	return gl.GraphLinkEvent[T]{}
}
