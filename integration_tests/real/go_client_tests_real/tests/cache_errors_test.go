package tests

import (
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

var flakyIds atomic.Int64

func flakyId() string { return fmt.Sprintf("go-%d-%d", time.Now().UnixNano(), flakyIds.Add(1)) }

func serverCalls(t *testing.T, c *gl.GraphLinkClient, id string) int {
	t.Helper()
	return must(c.Queries.CachedFlakyCalls(ctx(t), id)).CachedFlakyCalls
}

func TestAFailedResponseIsNotCached(t *testing.T) {
	c := newClient(t)
	id := flakyId()
	var exception *gl.GraphLinkException
	if _, err := c.Queries.CachedFlaky(ctx(t), id); !errors.As(err, &exception) {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
	expectEqual(t, serverCalls(t, c, id), 1, "calls after the failure")

	expectEqual(t, must(c.Queries.CachedFlaky(ctx(t), id)).CachedFlaky.Id, "user-1", "id")
	expectEqual(t, serverCalls(t, c, id), 2, "calls after the retry")

	expectEqual(t, must(c.Queries.CachedFlaky(ctx(t), id)).CachedFlaky.Id, "user-1", "id")
	expectEqual(t, serverCalls(t, c, id), 2, "calls after the cached read")
}

func TestAPartialFailureIsNotCached(t *testing.T) {
	c := newClient(t)
	id := flakyId()
	var exception *gl.GraphLinkException
	if _, err := c.Queries.CachedFlakyNullable(ctx(t), id); !errors.As(err, &exception) {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
	expectEqual(t, serverCalls(t, c, id), 1, "calls after the failure")

	expectEqual(t, must(c.Queries.CachedFlakyNullable(ctx(t), id)).CachedFlakyNullable.Id, "user-1", "id")
	expectEqual(t, serverCalls(t, c, id), 2, "calls after the retry")

	expectEqual(t, must(c.Queries.CachedFlakyNullable(ctx(t), id)).CachedFlakyNullable.Id, "user-1", "id")
	expectEqual(t, serverCalls(t, c, id), 2, "calls after the cached read")
}
