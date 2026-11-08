package tests

import (
	"context"
	"errors"
	"testing"
	"time"

	"graphlink.dev/resttests/generated"
)

func slowCall(ctx context.Context, client *generated.GraphLinkClient, op rune) error {
	switch op {
	case 'g':
		_, err := client.Queries.GetCount(ctx)
		return err
	case 'c':
		_, err := client.Queries.Count(ctx)
		return err
	case 'k':
		_, err := client.Queries.CachedStatus(ctx, 200)
		return err
	}
	_, err := client.Queries.Status(ctx, 200)
	return err
}

func TestCancelledCallReturnsPromptlyAndLeavesTheClientUsable(t *testing.T) {
	for _, op := range "gcpk" {
		for _, mode := range []string{"cancel", "timeout"} {
			op, mode := op, mode
			t.Run(string(op)+" "+mode, func(t *testing.T) {
				current = t
				postFault(t, "/_reset")
				client := newClient(t, clientOptions{base: faultURL()})
				postFault(t, "/_arm?fault=slow")
				var ctx context.Context
				var cancel context.CancelFunc
				if mode == "timeout" {
					ctx, cancel = context.WithTimeout(context.Background(), 200*time.Millisecond)
				} else {
					ctx, cancel = context.WithCancel(context.Background())
					time.AfterFunc(200*time.Millisecond, cancel)
				}
				defer cancel()
				started := time.Now()
				err := slowCall(ctx, client, op)
				if err == nil {
					t.Fatal("a cancelled call returned a value")
				}
				if !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
					t.Fatalf("the error does not say the call was cancelled: %v", err)
				}
				if elapsed := time.Since(started); elapsed > 700*time.Millisecond {
					t.Fatalf("the call waited %v for a response that nobody wanted", elapsed)
				}
				if err := slowCall(context.Background(), client, op); err != nil {
					t.Fatalf("client unusable after the cancellation: %v", err)
				}
			})
		}
	}
}
