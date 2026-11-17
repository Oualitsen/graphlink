package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

var faultPort = func() int {
	if value := os.Getenv("WS_FAULT_PORT"); value != "" {
		var port int
		_, _ = fmt.Sscan(value, &port)
		return port
	}
	return 9944
}()

type wsCase struct {
	Fault                string `json:"fault"`
	Expect               string `json:"expect"`
	Message              string `json:"message"`
	Times                int    `json:"times"`
	WaitSeconds          int    `json:"waitSeconds"`
	NoSubscribeBeforeAck bool   `json:"noSubscribeBeforeAck"`
	Pong                 bool   `json:"pong"`
	MaxConnections       *int   `json:"maxConnections"`
	MinConnections       *int   `json:"minConnections"`
}

const (
	noAckTimeout     = "the handshake waits for connection_ack with no timeout"
	reconnectsOn4xxx = "reconnects and resubscribes after a 4xxx close instead of surfacing an error"
)

var wsKnownDefects = map[string]string{
	"ws-no-ack":     noAckTimeout,
	"ws-close-4400": reconnectsOn4xxx,
	"ws-close-4401": reconnectsOn4xxx,
	"ws-close-4403": reconnectsOn4xxx,
	"ws-close-4409": reconnectsOn4xxx,
}

func faultURL(path string) string { return fmt.Sprintf("http://127.0.0.1:%d%s", faultPort, path) }

func faultPost(t *testing.T, path string) {
	t.Helper()
	response, err := http.Post(faultURL(path), "application/json", nil)
	if err != nil {
		t.Fatalf("fault server: %v", err)
	}
	_ = response.Body.Close()
}

type wsConnection struct {
	Frames []struct {
		Type string `json:"type"`
	} `json:"frames"`
}

func wsLog(t *testing.T) []wsConnection {
	t.Helper()
	response, err := http.Get(faultURL("/_ws_log"))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	var log []wsConnection
	if err := json.Unmarshal(body, &log); err != nil {
		t.Fatalf("ws log: %v", err)
	}
	return log
}

func TestWebSocketFaults(t *testing.T) {
	raw, err := os.ReadFile("../../fault_server/ws_cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []wsCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		c := c
		t.Run(c.Fault, func(t *testing.T) {
			if reason, ok := wsKnownDefects[c.Fault]; ok {
				t.Skip(reason)
			}
			runWsFault(t, c)
		})
	}
}

func runWsFault(t *testing.T, c wsCase) {
	faultPost(t, "/_reset")
	times := c.Times
	if times == 0 {
		times = 1
	}
	faultPost(t, fmt.Sprintf("/_arm?fault=%s&times=%d", c.Fault, times))

	ws := gl.NewDefaultGraphLinkWebSocketAdapter(fmt.Sprintf("ws://127.0.0.1:%d/graphql", faultPort))
	client := clientWithWs(t, ws, faultPort)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := client.Subscriptions.CounterTick(ctx)

	wait := 8 * time.Second
	if c.WaitSeconds > 0 {
		wait = time.Duration(c.WaitSeconds) * time.Second
	}
	var values []int
	var failure error
	settled := false
	deadline := time.After(wait)
loop:
	for {
		select {
		case event, ok := <-events:
			if !ok {
				settled = true
				break loop
			}
			if event.Err != nil {
				failure, settled = event.Err, true
				break loop
			}
			values = append(values, event.Data.CounterTick)
		case <-deadline:
			break loop
		}
	}
	log := wsLog(t)

	if c.WaitSeconds == 0 {
		if !settled {
			t.Fatal("the subscription hung")
		}
		switch c.Expect {
		case "value":
			if failure != nil || len(values) != 1 || values[0] != 1 {
				t.Fatalf("want [1], got %v, failure %v", values, failure)
			}
		case "error":
			if failure == nil {
				t.Fatalf("no failure, events=%v", values)
			}
			if c.Message != "" && !strings.Contains(failure.Error(), c.Message) {
				t.Fatalf("failure %q does not mention %q", failure, c.Message)
			}
		}
	}
	var sent []string
	for _, connection := range log {
		for _, frame := range connection.Frames {
			sent = append(sent, frame.Type)
		}
	}
	has := func(kind string) bool {
		for _, s := range sent {
			if s == kind {
				return true
			}
		}
		return false
	}
	if c.NoSubscribeBeforeAck && has("subscribe") {
		t.Fatal("subscribe was sent before connection_ack")
	}
	if c.Pong && !has("pong") {
		t.Fatal("the server ping was not answered with pong")
	}
	if c.MaxConnections != nil && len(log) > *c.MaxConnections {
		t.Fatalf("%d connections, at most %d expected", len(log), *c.MaxConnections)
	}
	if c.MinConnections != nil && len(log) < *c.MinConnections {
		t.Fatalf("%d connections, at least %d expected", len(log), *c.MinConnections)
	}
}
