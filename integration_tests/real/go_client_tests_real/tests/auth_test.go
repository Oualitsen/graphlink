package tests

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	gl "graphlink.dev/realtests/generated"
)

var tokens atomic.Int64

func uniqueToken() string { return fmt.Sprintf("go-%d-%d", time.Now().UnixNano(), tokens.Add(1)) }

func headers(values map[string]string) func(context.Context) (map[string]string, error) {
	return func(context.Context) (map[string]string, error) { return values, nil }
}

func clientWithHeaders(t *testing.T, provider func(context.Context) (map[string]string, error)) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{
		URL: httpURL(defaultPort), WsURL: wsURL(defaultPort), HeadersProvider: provider, WsHeadersProvider: provider,
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestHeadersProviderValuesReachTheServer(t *testing.T) {
	c := clientWithHeaders(t, headers(map[string]string{"X-Test": "v1"}))
	got := must(c.Queries.EchoHeader(ctx(t), "X-Test")).EchoHeader
	if got == nil || *got != "v1" {
		t.Fatalf("echoed header: %v", got)
	}
	if absent := must(c.Queries.EchoHeader(ctx(t), "X-Other")).EchoHeader; absent != nil {
		t.Fatalf("absent header echoed as %q", *absent)
	}
}

func TestHeadersProviderIsEvaluatedOnEveryRequest(t *testing.T) {
	var token atomic.Value
	token.Store("first")
	c := clientWithHeaders(t, func(context.Context) (map[string]string, error) {
		return map[string]string{"Authorization": "Bearer " + token.Load().(string)}, nil
	})
	expectEqual(t, must(c.Queries.WhoAmI(ctx(t))).WhoAmI, "first", "first token")
	token.Store("second")
	expectEqual(t, must(c.Queries.WhoAmI(ctx(t))).WhoAmI, "second", "rotated token")
}

func TestMissingTokenIsAGraphLinkException(t *testing.T) {
	_, err := newClient(t).Queries.WhoAmI(ctx(t))
	var exception *gl.GraphLinkException
	if !errors.As(err, &exception) || len(exception.Errors) == 0 {
		t.Fatalf("expected GraphLinkException, got %v", err)
	}
}

func TestConnectionInitCarriesTheToken(t *testing.T) {
	token := uniqueToken()
	c := clientWithHeaders(t, headers(map[string]string{"Authorization": "Bearer " + token}))
	end := drain(t, c.Subscriptions.SecureTicks(subscriptionContext(t), 3))
	if end.err != nil || len(end.data) != 3 || end.data[2].SecureTicks != 3 {
		t.Fatalf("ticks=%v err=%v", end.data, end.err)
	}
	expectEqual(t, must(newClient(t).Queries.SecureTickStarts(ctx(t), token)).SecureTickStarts, 1, "subscriptions started with the token")
}

func TestSubscriptionWithoutATokenFails(t *testing.T) {
	c := clientOnNewWs(t)
	end := drain(t, c.Subscriptions.SecureTicks(subscriptionContext(t), 3))
	if end.err == nil || len(end.data) != 0 {
		t.Fatalf("ticks=%v err=%v", end.data, end.err)
	}
}
