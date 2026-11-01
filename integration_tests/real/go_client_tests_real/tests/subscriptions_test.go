package tests

import (
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

func clientOnNewWs(t *testing.T) *gl.GraphLinkClient {
	t.Helper()
	return clientWithWs(t, newWsAdapter(defaultPort), defaultPort)
}

func TestUserCreatedFirstEventIsAlice(t *testing.T) {
	c := clientOnNewWs(t)
	event := firstEvent(t, c.Subscriptions.UserCreated(subscriptionContext(t)))
	expectEqual(t, event.Data.UserCreated.Id, "user-1", "id")
	expectEqual(t, event.Data.UserCreated.Name, "Alice Smith", "name")
	expectEqual(t, event.Data.UserCreated.Status, gl.UserStatusActive, "status")
}

func TestUserCreatedEmitsMultipleEvents(t *testing.T) {
	c := clientOnNewWs(t)
	events := c.Subscriptions.UserCreated(subscriptionContext(t))
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-1", "first")
	expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-2", "second")
}

func TestUserCreatedAndCounterTickRunConcurrentlyOnOneConnection(t *testing.T) {
	c := clientOnNewWs(t)
	users := c.Subscriptions.UserCreated(subscriptionContext(t))
	counter := c.Subscriptions.CounterTick(subscriptionContext(t))
	expectEqual(t, firstEvent(t, users).Data.UserCreated.Id, "user-1", "user")
	_ = firstEvent(t, counter).Data.CounterTick
}

func TestTwoUserStatusChangedSubscriptionsAreIndependent(t *testing.T) {
	c := clientOnNewWs(t)
	one := c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-1")
	two := c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-2")
	first, second := firstEvent(t, one), firstEvent(t, two)
	expectEqual(t, first.Data.UserStatusChanged.Id, "user-1", "first id")
	expectEqual(t, first.Data.UserStatusChanged.Status, gl.UserStatusActive, "first status")
	expectEqual(t, second.Data.UserStatusChanged.Id, "user-2", "second id")
	expectEqual(t, second.Data.UserStatusChanged.Status, gl.UserStatusInactive, "second status")
}

func TestThreeConcurrentSubscriptions(t *testing.T) {
	c := clientOnNewWs(t)
	a := c.Subscriptions.UserCreated(subscriptionContext(t))
	b := c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-1")
	d := c.Subscriptions.CounterTick(subscriptionContext(t))
	expectEqual(t, firstEvent(t, a).Data.UserCreated.Id, "user-1", "userCreated")
	expectEqual(t, firstEvent(t, b).Data.UserStatusChanged.Id, "user-1", "userStatusChanged")
	_ = firstEvent(t, d).Data.CounterTick
}

func TestCancellingOneSubscriptionDoesNotStopTheOther(t *testing.T) {
	c := clientOnNewWs(t)
	counter := c.Subscriptions.CounterTick(subscriptionContext(t))
	users := c.Subscriptions.UserCreated(subscriptionContext(t))
	deadline := time.After(10 * time.Second)
	for done := false; !done; {
		select {
		case _, ok := <-users:
			done = !ok
		case <-deadline:
			t.Fatal("userCreated never completed")
		}
	}
	_ = firstEvent(t, counter)
}

func TestTwoIdenticalUserCreatedSubscriptionsReceiveAllEvents(t *testing.T) {
	c := clientOnNewWs(t)
	one := c.Subscriptions.UserCreated(subscriptionContext(t))
	two := c.Subscriptions.UserCreated(subscriptionContext(t))
	for _, events := range []<-chan gl.GraphLinkEvent[gl.UserCreatedResponse]{one, two} {
		expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-1", "first")
		expectEqual(t, firstEvent(t, events).Data.UserCreated.Id, "user-2", "second")
	}
}

func TestTwoIdenticalUserStatusChangedSubscriptions(t *testing.T) {
	c := clientOnNewWs(t)
	one := c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-1")
	two := c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-1")
	for _, event := range []gl.GraphLinkEvent[gl.UserStatusChangedResponse]{firstEvent(t, one), firstEvent(t, two)} {
		expectEqual(t, event.Data.UserStatusChanged.Id, "user-1", "id")
		expectEqual(t, event.Data.UserStatusChanged.Status, gl.UserStatusActive, "status")
	}
}

func TestUserCreatedAndUserCreatedsReturnDistinctTypedStreams(t *testing.T) {
	c := clientOnNewWs(t)
	single := c.Subscriptions.UserCreated(subscriptionContext(t))
	list := c.Subscriptions.UserCreateds(subscriptionContext(t), []string{"user-1", "user-2"})
	expectEqual(t, firstEvent(t, single).Data.UserCreated.Id, "user-1", "single")
	users := firstEvent(t, list).Data.UserCreateds
	expectEqual(t, len(users), 2, "list length")
	expectEqual(t, users[0].Id, "user-1", "first")
	expectEqual(t, users[1].Id, "user-2", "second")
}

func TestUserStatusChangedPerUser(t *testing.T) {
	c := clientOnNewWs(t)
	event := firstEvent(t, c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-1"))
	expectEqual(t, event.Data.UserStatusChanged.Id, "user-1", "id")
	expectEqual(t, event.Data.UserStatusChanged.Status, gl.UserStatusActive, "status")
	bob := firstEvent(t, c.Subscriptions.UserStatusChanged(subscriptionContext(t), "user-2"))
	expectEqual(t, bob.Data.UserStatusChanged.Id, "user-2", "id")
	expectEqual(t, bob.Data.UserStatusChanged.Status, gl.UserStatusInactive, "status")
}
