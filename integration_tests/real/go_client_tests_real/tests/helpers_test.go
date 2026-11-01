package tests

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

const (
	defaultPort = 9999
	uploadPort  = 9998
)

func httpURL(port int) string { return fmt.Sprintf("http://localhost:%d/graphql", port) }
func wsURL(port int) string   { return fmt.Sprintf("ws://localhost:%d/graphql", port) }

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	return c
}

func newClient(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	return newClientOn(t, defaultPort)
}

func newClientOn(t *testing.T, port int) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{URL: httpURL(port), WsURL: wsURL(port)})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func newUploadClient(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	main := gl.NewGraphLinkHttpAdapter(httpURL(defaultPort))
	upload := gl.NewGraphLinkHttpAdapter(httpURL(uploadPort))
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{
		Adapter:       main.Call,
		UploadAdapter: upload.MultipartCall,
		WsAdapter:     gl.NewDefaultGraphLinkWebSocketAdapter(wsURL(defaultPort)),
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func newWsAdapter(port int) *gl.DefaultGraphLinkWebSocketAdapter {
	return gl.NewDefaultGraphLinkWebSocketAdapter(wsURL(port))
}

func clientWithWs(t *testing.T, ws *gl.DefaultGraphLinkWebSocketAdapter, httpPort int) *gl.GraphLinkClient {
	t.Helper()
	adapter := gl.NewGraphLinkHttpAdapter(httpURL(httpPort))
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{Adapter: adapter.Call, WsAdapter: ws})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ws.Close() })
	return client
}

func subscriptionContext(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	return c
}

func nextEvent[T any](t *testing.T, events <-chan gl.GraphLinkEvent[T], timeout time.Duration) gl.GraphLinkEvent[T] {
	t.Helper()
	select {
	case event, ok := <-events:
		if !ok {
			t.Fatal("subscription closed before an event arrived")
		}
		return event
	case <-time.After(timeout):
		t.Fatal("timed out waiting for subscription event")
	}
	return gl.GraphLinkEvent[T]{}
}

func firstEvent[T any](t *testing.T, events <-chan gl.GraphLinkEvent[T]) gl.GraphLinkEvent[T] {
	t.Helper()
	event := nextEvent(t, events, 10*time.Second)
	if event.Err != nil {
		t.Fatalf("subscription error: %v", event.Err)
	}
	return event
}

func expectEqual[T comparable](t *testing.T, got, want T, what string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: got %v, want %v", what, got, want)
	}
}

func minimalInput() gl.CreateUserInput {
	return gl.CreateUserInput{
		Name: "Alice Smith", Email: "alice@test.com", Status: gl.UserStatusActive,
		Address: gl.AddressInput{Street: "123 Main St", City: "Springfield", Country: "US"},
	}
}

func serverJar() string { return os.Getenv("SERVER_JAR") }

func killPort(port int) {
	_ = exec.Command("bash", "-c", fmt.Sprintf("lsof -ti :%d -sTCP:LISTEN | xargs kill -9 2>/dev/null || true", port)).Run()
	time.Sleep(500 * time.Millisecond)
}

func startServer(t *testing.T, port int) {
	t.Helper()
	jar := serverJar()
	if jar == "" {
		t.Skip("SERVER_JAR env var not set — run via make reconnect-test")
	}
	killPort(port)
	cmd := exec.Command("java", "-jar", jar, fmt.Sprintf("--server.port=%d", port), "--management.server.port=-1")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); killPort(port) })
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		if conn, err := net.DialTimeout("tcp", fmt.Sprintf("localhost:%d", port), time.Second); err == nil {
			_ = conn.Close()
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
	t.Fatalf("server on port %d did not start within 30 s", port)
}
