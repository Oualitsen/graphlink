package tests

import (
	"errors"
	"testing"
	"time"

	gl "graphlink.dev/serverintegration/generated"
)

func TestGreetInterceptedAppendsTheRunBeforeMarker(t *testing.T) {
	c := newClient(t)
	if got := must(c.Queries.GreetIntercepted(ctx(t), "Ada")).GreetIntercepted.Message; got != "Hello, Ada(runBefore)" {
		t.Fatalf("got %q", got)
	}
}

func TestGreetPlainIsNotIntercepted(t *testing.T) {
	c := newClient(t)
	if got := must(c.Queries.GreetPlain(ctx(t), "Ada")).GreetPlain.Message; got != "Hello, Ada" {
		t.Fatalf("got %q", got)
	}
}

func TestGreetingReceivedBakesTheMarkerIntoEveryEmittedGreeting(t *testing.T) {
	c := newClient(t)
	events := c.Subscriptions.GreetingReceived(subscriptionContext(t))
	time.Sleep(500 * time.Millisecond)
	must(c.Mutations.SendGreeting(ctx(t), "Ada"))
	event := firstEvent(t, events)
	if event.Err != nil || event.Data.GreetingReceived.Message != "Hello, Ada(runBefore)" {
		t.Fatalf("unexpected event: %+v", event)
	}
}

func TestTeamMembersInterceptedMappingAllowsRoleAuth(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.ListTeams(ctx(t), gl.ListTeamsFieldArgs{MembersRole: "auth"}))
	names := map[string]bool{}
	for _, m := range res.ListTeams[0].Members {
		names[m.Name] = true
	}
	if len(names) != 2 || !names["Ada"] || !names["Grace"] {
		t.Fatalf("unexpected members: %v", names)
	}
}

func TestTeamMembersInterceptedMappingDeniesAnyOtherRole(t *testing.T) {
	c := newClient(t)
	_, err := c.Queries.ListTeams(ctx(t), gl.ListTeamsFieldArgs{MembersRole: "wrong"})
	var exception *gl.GraphLinkException
	if !errors.As(err, &exception) {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
}
