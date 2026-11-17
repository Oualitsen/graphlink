package tests

import (
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var concurrencyNames atomic.Int64

func freshCounterName() string {
	return fmt.Sprintf("go-%d-%d", time.Now().UnixNano(), concurrencyNames.Add(1))
}

func TestConcurrentCachedRestCallsForTwoKeysMakeTwoCalls(t *testing.T) {
	ctx, client := setup(t)
	name := freshCounterName()
	var wg sync.WaitGroup
	for _, suffix := range []string{"-a", "-b"} {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			must(client.Queries.CounterSlow(ctx, n, 300))
		}(name + suffix)
	}
	wg.Wait()
	eq(t, must(client.Queries.CounterCalls(ctx, name+"-a")).N, 1)
	eq(t, must(client.Queries.CounterCalls(ctx, name+"-b")).N, 1)
}

func TestConcurrentCachedRestCallsForTheSameKeyShareOneCall(t *testing.T) {
	ctx, client := setup(t)
	name := freshCounterName()
	var wg sync.WaitGroup
	results := make([]int, 3)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i] = must(client.Queries.CounterSlow(ctx, name, 300)).N
		}(i)
	}
	wg.Wait()
	eq(t, results, []int{1, 1, 1})
	eq(t, must(client.Queries.CounterCalls(ctx, name)).N, 1)
}

func TestACachedRestResponseInFlightDuringAnInvalidationIsNotStored(t *testing.T) {
	ctx, client := setup(t)
	name := freshCounterName()
	slow := make(chan int, 1)
	go func() { slow <- must(client.Queries.CounterSlow(ctx, name, 600)).N }()
	time.Sleep(150 * time.Millisecond)
	must(client.Mutations.TouchSlow(ctx, name))
	eq(t, <-slow, 1)
	eq(t, must(client.Queries.CounterSlow(ctx, name, 600)).N, 2)
}
