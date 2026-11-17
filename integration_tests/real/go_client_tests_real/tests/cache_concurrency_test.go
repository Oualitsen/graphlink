package tests

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var concurrencyIds atomic.Int64

func freshConcurrencyId(t *testing.T) string {
	return fmt.Sprintf("go-%d-%d", time.Now().UnixNano(), concurrencyIds.Add(1))
}

func TestConcurrentRequestsForTwoKeysMakeTwoCalls(t *testing.T) {
	c := newClient(t)
	id := freshConcurrencyId(t)
	var wg sync.WaitGroup
	for _, key := range []string{id + "-a", id + "-b"} {
		wg.Add(1)
		go func(key string) {
			defer wg.Done()
			if _, err := c.Queries.CachedSlow(ctx(t), key, 300); err != nil {
				t.Error(err)
			}
		}(key)
	}
	wg.Wait()
	for _, key := range []string{id + "-a", id + "-b"} {
		expectEqual(t, must(c.Queries.CachedSlowCalls(ctx(t), key)).CachedSlowCalls, 1, "calls "+key)
	}
}

func TestConcurrentRequestsForTheSameKeyShareOneCall(t *testing.T) {
	c := newClient(t)
	id := freshConcurrencyId(t)
	versions := make([]int, 3)
	var wg sync.WaitGroup
	for i := range versions {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			res, err := c.Queries.CachedSlow(ctx(t), id, 300)
			if err != nil {
				t.Error(err)
			}
			versions[i] = res.CachedSlow
		}(i)
	}
	wg.Wait()
	expectEqual(t, versions[0]+versions[1]+versions[2], 0, "versions")
	expectEqual(t, must(c.Queries.CachedSlowCalls(ctx(t), id)).CachedSlowCalls, 1, "calls")
}

func TestResponseInFlightDuringInvalidationIsNotStored(t *testing.T) {
	c := newClient(t)
	id := freshConcurrencyId(t)
	type result struct {
		version int
		err     error
	}
	done := make(chan result, 1)
	go func() {
		res, err := c.Queries.CachedSlow(ctx(t), id, 600)
		done <- result{res.CachedSlow, err}
	}()
	time.Sleep(150 * time.Millisecond)
	must(c.Mutations.BumpSlow(ctx(t), id))
	r := <-done
	if r.err != nil {
		t.Fatal(r.err)
	}
	expectEqual(t, r.version, 0, "in-flight version")
	expectEqual(t, must(c.Queries.CachedSlow(ctx(t), id, 600)).CachedSlow, 1, "version after invalidation")
}
