package tests

import (
	"context"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

const reconnectPort = 9930

func reconnectClient(t *testing.T, configure func(*gl.DefaultGraphLinkWebSocketAdapter)) (*gl.GraphLinkClient, *atomic.Int32) {
	t.Helper()
	if serverJar() == "" {
		t.Skip("SERVER_JAR env var not set — run via make reconnect-test")
	}
	startServer(t, reconnectPort)
	ws := newWsAdapter(reconnectPort)
	var reconnects atomic.Int32
	ws.AddReconnectListener(func() { reconnects.Add(1) })
	if configure != nil {
		configure(ws)
	}
	return clientWithWs(t, ws, reconnectPort), &reconnects
}

func labelStarts(t *testing.T, c *gl.GraphLinkClient, label string) int {
	t.Helper()
	return must(c.Queries.LabelTickStarts(ctx(t), label)).LabelTickStarts
}

func awaitReconnects(t *testing.T, reconnects *atomic.Int32, want int32) {
	t.Helper()
	deadline := time.Now().Add(time.Minute)
	for reconnects.Load() < want {
		if time.Now().After(deadline) {
			t.Fatalf("the adapter did not reconnect (%d/%d)", reconnects.Load(), want)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func awaitLabelEvent(t *testing.T, events <-chan gl.GraphLinkEvent[gl.LabelTicksResponse], label string) {
	t.Helper()
	deadline := time.After(time.Minute)
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatalf("stream %s closed", label)
			}
			if event.Err == nil && strings.HasPrefix(event.Data.LabelTicks, label+"-") {
				return
			}
		case <-deadline:
			t.Fatalf("no event for %s after the restart", label)
		}
	}
}

func expectNoEvent(t *testing.T, events <-chan gl.GraphLinkEvent[gl.LabelTicksResponse], wait time.Duration) {
	t.Helper()
	select {
	case event, ok := <-events:
		if ok {
			t.Fatalf("unexpected event after the restart: %+v", event)
		}
	case <-time.After(wait):
	}
}

func TestReconnectResubscribesWithTheSameVariables(t *testing.T) {
	c, reconnects := reconnectClient(t, nil)
	events := c.Subscriptions.LabelTicks(subscriptionContext(t), "bob", 1000)
	expectEqual(t, firstEvent(t, events).Data.LabelTicks, "bob-1", "first event")

	startServer(t, reconnectPort)
	awaitReconnects(t, reconnects, 1)
	awaitLabelEvent(t, events, "bob")
	expectEqual(t, labelStarts(t, c, "bob"), 1, "starts on the restarted server")
}

func TestReconnectDoesNotResubscribeACompletedSubscription(t *testing.T) {
	c, _ := reconnectClient(t, nil)
	events := c.Subscriptions.LabelTicks(subscriptionContext(t), "done", 2)
	end := drain(t, events)
	expectEqual(t, len(end.data), 2, "events before completion")

	startServer(t, reconnectPort)
	time.Sleep(6 * time.Second)
	expectEqual(t, labelStarts(t, c, "done"), 0, "starts on the restarted server")
	expectNoEvent(t, events, 0)
}

func TestReconnectDoesNotReviveACancelledSubscription(t *testing.T) {
	c, _ := reconnectClient(t, nil)
	subscription, cancel := context.WithCancel(context.Background())
	events := c.Subscriptions.LabelTicks(subscription, "cancelled", 1000)
	firstEvent(t, events)
	cancel()
	time.Sleep(time.Second)

	startServer(t, reconnectPort)
	time.Sleep(6 * time.Second)
	expectEqual(t, labelStarts(t, c, "cancelled"), 0, "starts on the restarted server")
}

func TestReconnectResumesEveryOpenSubscriptionOnOneSocket(t *testing.T) {
	c, reconnects := reconnectClient(t, nil)
	a := c.Subscriptions.LabelTicks(subscriptionContext(t), "a", 1000)
	b := c.Subscriptions.LabelTicks(subscriptionContext(t), "b", 1000)
	firstEvent(t, a)
	firstEvent(t, b)

	startServer(t, reconnectPort)
	awaitReconnects(t, reconnects, 1)
	awaitLabelEvent(t, a, "a")
	awaitLabelEvent(t, b, "b")
	expectEqual(t, labelStarts(t, c, "a"), 1, "starts of a")
	expectEqual(t, labelStarts(t, c, "b"), 1, "starts of b")
}

func TestReconnectDuringConnectionInitSubscribesOnce(t *testing.T) {
	c, _ := reconnectClient(t, func(ws *gl.DefaultGraphLinkWebSocketAdapter) {
		ws.HeadersProvider = headers(map[string]string{"Ack-Delay": "3000"})
	})
	events := c.Subscriptions.LabelTicks(subscriptionContext(t), "init", 1000)
	time.Sleep(time.Second)

	startServer(t, reconnectPort)
	awaitLabelEvent(t, events, "init")
	time.Sleep(2 * time.Second)
	expectEqual(t, labelStarts(t, c, "init"), 1, "starts on the restarted server")
}

func TestReconnectGivesUpWithAVisibleError(t *testing.T) {
	c, _ := reconnectClient(t, func(ws *gl.DefaultGraphLinkWebSocketAdapter) {
		ws.MaxReconnectAttempts = 2
		ws.MaxReconnectDelay = time.Second
	})
	events := c.Subscriptions.LabelTicks(subscriptionContext(t), "giveup", 1000)
	firstEvent(t, events)
	killPort(reconnectPort)

	deadline := time.After(time.Minute)
	for {
		select {
		case event, ok := <-events:
			if !ok {
				t.Fatal("the stream closed without an error")
			}
			if event.Err != nil {
				return
			}
		case <-deadline:
			t.Fatal("the stream neither failed nor ended after the reconnect attempts ran out")
		}
	}
}
