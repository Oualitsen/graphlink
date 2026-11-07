package tests

import (
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

type streamEnd[T any] struct {
	data   []T
	err    error
	closed bool
}

func drain[T any](t *testing.T, events <-chan gl.GraphLinkEvent[T]) streamEnd[T] {
	t.Helper()
	var end streamEnd[T]
	deadline := time.After(10 * time.Second)
	for {
		select {
		case event, ok := <-events:
			if !ok {
				end.closed = true
				return end
			}
			if event.Err != nil {
				end.err = event.Err
				continue
			}
			end.data = append(end.data, event.Data)
		case <-deadline:
			t.Fatal("stream never ended")
		}
	}
}

func TestSubscriptionArgumentsOfEveryShapeRoundTrip(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.SubEchoArgs(subscriptionContext(t), []int{1, 2}, []gl.Spelling{gl.SpellingXY, gl.SpellingHttp2Ok}, gl.SubEchoArgsOptions{
		B: []*int{intp(1), nil},
		C: [][]int{{1}, {}, {2, 3}},
		F: []*gl.Spelling{nil, sp(gl.SpellingV1)},
	}))
	expectEqual(t, len(end.data), 1, "events")
	r := end.data[0].SubEchoArgs
	expectDeep(t, r.A, []int{1, 2}, "a")
	expectDeep(t, r.B, []*int{intp(1), nil}, "b")
	expectDeep(t, r.C, [][]int{{1}, {}, {2, 3}}, "c")
	expectDeep(t, r.E, []gl.Spelling{gl.SpellingXY, gl.SpellingHttp2Ok}, "e")
	expectDeep(t, r.F, []*gl.Spelling{nil, sp(gl.SpellingV1)}, "f")
}

func TestSubscriptionOmittedArgumentsAreNullAndDefaultsApply(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.SubEchoArgs(subscriptionContext(t), []int{}, []gl.Spelling{}))
	r := end.data[0].SubEchoArgs
	if r.B != nil || r.C != nil || r.F != nil {
		t.Fatal("omitted lists must come back nil")
	}
	expectDeep(t, r.G, []gl.Spelling{gl.SpellingA, gl.SpellingB2}, "g")
	expectEqual(t, r.One, gl.OnlyOneOnly, "one")
}

func TestSubscriptionInputObjectRoundTrips(t *testing.T) {
	c := clientOnNewWs(t)
	input := gl.NewListsInput()
	input.A = []int{3, 4}
	input.B = []*int{nil, intp(5)}
	input.C = [][]int{{1, 2}, {}}
	input.E = []gl.Spelling{gl.SpellingSnakeCase2}
	input.F = []*gl.Spelling{sp(gl.SpellingA), nil}
	input.G = []gl.Spelling{gl.SpellingV1}
	r := drain(t, c.Subscriptions.SubEchoInput(subscriptionContext(t), input)).data[0].SubEchoInput
	expectDeep(t, r.A, []int{3, 4}, "a")
	expectDeep(t, r.B, []*int{nil, intp(5)}, "b")
	expectDeep(t, r.C, [][]int{{1, 2}, {}}, "c")
	expectDeep(t, r.E, []gl.Spelling{gl.SpellingSnakeCase2}, "e")
	expectDeep(t, r.F, []*gl.Spelling{sp(gl.SpellingA), nil}, "f")
	expectDeep(t, r.G, []gl.Spelling{gl.SpellingV1}, "g")
}

func TestServerCompletionDeliversEveryEventThenClosesTheChannel(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.FiniteTicks(subscriptionContext(t), 5))
	got := make([]int, 0, len(end.data))
	for _, e := range end.data {
		got = append(got, e.FiniteTicks)
	}
	expectDeep(t, got, []int{1, 2, 3, 4, 5}, "ticks")
	expectEqual(t, end.closed, true, "closed")
	if end.err != nil {
		t.Fatalf("unexpected error: %v", end.err)
	}
}

func TestServerCompletionWithoutEventsClosesTheChannel(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.FiniteTicks(subscriptionContext(t), 0))
	expectEqual(t, len(end.data), 0, "events")
	expectEqual(t, end.closed, true, "closed")
}

func TestEventsBeforeTheFailureArriveThenTheError(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.FlakyTicks(subscriptionContext(t), 3))
	got := make([]int, 0, len(end.data))
	for _, e := range end.data {
		got = append(got, e.FlakyTicks)
	}
	expectDeep(t, got, []int{1, 2, 3}, "ticks")
	if end.err == nil {
		t.Fatal("expected the stream to fail")
	}
}

func TestFailureBeforeTheFirstEvent(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.FlakyTicks(subscriptionContext(t), 0))
	expectEqual(t, len(end.data), 0, "events")
	if end.err == nil {
		t.Fatal("expected the stream to fail")
	}
}

func TestFailedStreamDoesNotBreakTheNextSubscription(t *testing.T) {
	c := clientOnNewWs(t)
	drain(t, c.Subscriptions.FlakyTicks(subscriptionContext(t), 1))
	end := drain(t, c.Subscriptions.FiniteTicks(subscriptionContext(t), 2))
	expectEqual(t, len(end.data), 2, "events")
}
