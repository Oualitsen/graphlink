package tests

import (
	"context"
	"os/exec"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestSubscriptionReconnectCounterTickResumesAfterServerKill(t *testing.T) {
	jar := serverJar()
	if jar == "" {
		t.Skip("SERVER_JAR env var not set — run via make reconnect-test")
	}
	const port = 9996
	startServer(t, port)
	ws := newWsAdapter(port)
	var reconnected atomic.Bool
	ws.AddReconnectListener(func() { reconnected.Store(true) })
	c := clientWithWs(t, ws, port)
	events := c.Subscriptions.CounterTick(subscriptionContext(t))

	seen := map[int]bool{}
	deadline := time.After(2 * time.Minute)
	restarted := false
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("stream closed")
			}
			if event.Err != nil {
				continue
			}
			tick := event.Data.CounterTick
			if tick == 4 && !restarted {
				restarted = true
				killPort(port)
				cmd := exec.Command("java", "-jar", jar, "--server.port=9996", "--management.server.port=-1")
				if err := cmd.Start(); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = cmd.Process.Kill() })
			}
			if seen[tick] {
				if !reconnected.Load() {
					t.Fatal("the adapter should have reconnected after the server restart")
				}
				for _, want := range []int{1, 2, 3, 4} {
					if !seen[want] {
						t.Fatalf("missing tick %d before the restart: %v", want, seen)
					}
				}
				return
			}
			seen[tick] = true
		case <-deadline:
			t.Fatal("subscription did not resume after the server restart")
		}
	}
}

func TestSubscriptionReconnectRetriesIndefinitelyWhenCapIsDisabled(t *testing.T) {
	const port = 9994
	const targetAttempts = 10
	killPort(port)
	ws := newWsAdapter(port)
	ws.MaxReconnectAttempts = -1
	ws.MaxReconnectDelay = 2 * time.Second
	var reconnected atomic.Bool
	ws.AddReconnectListener(func() { reconnected.Store(true) })
	c := clientWithWs(t, ws, port)
	c.Subscriptions.CounterTick(subscriptionContext(t))

	deadline := time.Now().Add(time.Minute)
	for ws.ReconnectAttempts() < targetAttempts {
		if time.Now().After(deadline) {
			t.Fatalf("only reached %d/%d attempts", ws.ReconnectAttempts(), targetAttempts)
		}
		time.Sleep(500 * time.Millisecond)
	}
	if reconnected.Load() {
		t.Fatal("no successful reconnect expected — no server is running")
	}
}

func TestSubscriptionReconnectConnectsOnceTheServerBecomesAvailable(t *testing.T) {
	if serverJar() == "" || strings.TrimSpace(serverJar()) == "" {
		t.Skip("SERVER_JAR env var not set — run via make reconnect-test")
	}
	const port = 9997
	killPort(port)
	ws := newWsAdapter(port)
	var reconnected atomic.Bool
	ws.AddReconnectListener(func() { reconnected.Store(true) })
	c := clientWithWs(t, ws, port)
	events := c.Subscriptions.CounterTick(subscriptionContext(t))

	startServer(t, port)
	deadline := time.After(time.Minute)
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("stream closed")
			}
			if event.Err != nil {
				continue
			}
			if event.Data.CounterTick <= 0 {
				t.Fatalf("unexpected tick %d", event.Data.CounterTick)
			}
			if !reconnected.Load() {
				t.Fatal("onReconnect should fire when the server becomes available")
			}
			return
		case <-deadline:
			t.Fatal("never received a tick once the server was up")
		}
	}
}

func TestSubscriptionReconnectSendsTheRotatedTokenOnConnectionInit(t *testing.T) {
	if serverJar() == "" {
		t.Skip("SERVER_JAR env var not set — run via make reconnect-test")
	}
	const port = 9996
	first, second := uniqueToken(), uniqueToken()
	var token atomic.Value
	token.Store(first)

	startServer(t, port)
	ws := newWsAdapter(port)
	ws.HeadersProvider = func(context.Context) (map[string]string, error) {
		return map[string]string{"Authorization": "Bearer " + token.Load().(string)}, nil
	}
	c := clientWithWs(t, ws, port)
	events := c.Subscriptions.SecureTicks(subscriptionContext(t), 1000)
	if event := nextEvent(t, events, 10*time.Second); event.Err != nil {
		t.Fatalf("first event: %v", event.Err)
	}
	expectEqual(t, must(c.Queries.SecureTickStarts(ctx(t), first)).SecureTickStarts, 1, "starts with the first token")

	token.Store(second)
	killPort(port)
	cmd := exec.Command("java", "-jar", serverJar(), "--server.port=9996", "--management.server.port=-1")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill() })

	deadline := time.Now().Add(time.Minute)
	for {
		if time.Now().After(deadline) {
			t.Fatal("the subscription was not resumed with the rotated token")
		}
		if starts, err := c.Queries.SecureTickStarts(ctx(t), second); err == nil && starts.SecureTickStarts == 1 {
			break
		}
		time.Sleep(time.Second)
	}
	expectEqual(t, must(c.Queries.SecureTickStarts(ctx(t), first)).SecureTickStarts, 0, "starts with the stale token on the restarted server")
}
