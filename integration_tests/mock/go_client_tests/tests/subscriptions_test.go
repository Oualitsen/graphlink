package tests

import (
	"context"
	"testing"
	"time"

	gl "graphlink.dev/mocktests/generated"
)

func TestUserCreatedSingleEvent(t *testing.T) {
	h := newHarness(t)
	events := h.client.Subscriptions.UserCreated(h.ctx)
	h.ws.WaitSubscriptionReady(t)
	h.ws.PushEvent(object{"userCreated": userAliceJson})
	event := firstEvent(t, events)
	if event.Err != nil {
		t.Fatal(event.Err)
	}
	expectEqual(t, event.Data.UserCreated.Id, "user-1", "id")
	expectEqual(t, event.Data.UserCreated.Name, "Alice Smith", "name")
	expectEqual(t, event.Data.UserCreated.Status, gl.UserStatusActive, "status")
}

func TestUserCreatedEmitsMultipleEventsInOrder(t *testing.T) {
	h := newHarness(t)
	events := h.client.Subscriptions.UserCreated(h.ctx)
	h.ws.WaitSubscriptionReady(t)
	h.ws.PushEvent(object{"userCreated": userAliceJson})
	h.ws.PushEvent(object{"userCreated": userBobJson})
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-1", "first")
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-2", "second")
}

func TestCompleteMessageClosesTheChannel(t *testing.T) {
	h := newHarness(t)
	events := h.client.Subscriptions.UserCreated(h.ctx)
	h.ws.WaitSubscriptionReady(t)
	h.ws.PushEvent(object{"userCreated": userAliceJson})
	h.ws.PushComplete()
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-1", "event before complete")
	select {
	case _, ok := <-events:
		if ok {
			t.Fatal("expected the channel to be closed")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("channel was not closed")
	}
}

func TestCancellingStopsFurtherDelivery(t *testing.T) {
	h := newHarness(t)
	ctx, cancel := context.WithCancel(h.ctx)
	events := h.client.Subscriptions.UserCreated(ctx)
	h.ws.WaitSubscriptionReady(t)
	h.ws.PushEvent(object{"userCreated": userAliceJson})
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-1", "first event")
	cancel()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case _, ok := <-events:
			if !ok {
				return
			}
		case <-deadline:
			t.Fatal("channel was not closed after cancel")
		}
	}
}

func TestCancellingSendsComplete(t *testing.T) {
	h := newHarness(t)
	ctx, cancel := context.WithCancel(h.ctx)
	h.client.Subscriptions.UserCreated(ctx)
	h.ws.WaitSubscriptionReady(t)
	cancel()
	deadline := time.After(5 * time.Second)
	for {
		for _, message := range h.ws.SentMessages() {
			if message["type"] == "complete" {
				return
			}
		}
		select {
		case <-deadline:
			t.Fatal("no complete message was sent")
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestUserStatusChanged(t *testing.T) {
	h := newHarness(t)
	events := h.client.Subscriptions.UserStatusChanged(h.ctx, "user-42")
	h.ws.WaitSubscriptionReady(t)
	h.ws.PushEvent(object{"userStatusChanged": userAliceJson})
	event := firstEvent(t, events)
	expectEqual(t, event.Data.UserStatusChanged.Id, "user-1", "id")
	expectEqual(t, event.Data.UserStatusChanged.Status, gl.UserStatusActive, "status")
	for _, message := range h.ws.SentMessages() {
		if message["type"] == "subscribe" {
			variables := message["payload"].(map[string]any)["variables"].(map[string]any)
			expectEqual(t, variables["userId"].(string), "user-42", "userId variable")
			return
		}
	}
	t.Fatal("no subscribe message was sent")
}
