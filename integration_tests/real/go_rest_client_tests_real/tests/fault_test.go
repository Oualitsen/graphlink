package tests

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"graphlink.dev/resttests/generated"
)

type faultCase struct {
	Fault  string `json:"fault"`
	Ops    string `json:"ops"`
	Expect string `json:"expect"`
}

var knownDefects = map[string]string{
}

var opNames = map[rune]string{'g': "GraphQL getCount", 'c': "REST count", 'p': "REST status"}

func faultURL() string {
	if comma {
		return "http://127.0.0.1:9963"
	}
	return "http://127.0.0.1:9962"
}

func postFault(t *testing.T, path string) {
	t.Helper()
	response, err := http.Post(faultURL()+path, "text/plain", nil)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
}

func loadFaultCases(t *testing.T) []faultCase {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	var raw []byte
	for {
		raw, err = os.ReadFile(filepath.Join(dir, "fault_server", "cases.json"))
		if err == nil {
			break
		}
		if parent := filepath.Dir(dir); parent != dir {
			dir = parent
			continue
		}
		t.Fatal(err)
	}
	var cases []faultCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	return cases
}

func callFault(ctx context.Context, client *generated.GraphLinkClient, op rune) (any, error) {
	switch op {
	case 'g':
		return client.Queries.GetCount(ctx)
	case 'c':
		return client.Queries.Count(ctx)
	}
	return client.Queries.Status(ctx, 200)
}

func assertHealthy(ctx context.Context, t *testing.T, client *generated.GraphLinkClient, op rune) {
	t.Helper()
	switch op {
	case 'g':
		if got := must(client.Queries.GetCount(ctx)).GetCount; got != 19 {
			t.Fatalf("client unusable after the fault: getCount = %d", got)
		}
	case 'c':
		if got := must(client.Queries.Count(ctx)); got != 7 {
			t.Fatalf("client unusable after the fault: count = %d", got)
		}
	default:
		if got := must(client.Queries.Status(ctx, 200)); got == nil || got.Name != "Pen" {
			t.Fatalf("client unusable after the fault: status = %v", got)
		}
	}
}

func TestFaultInjection(t *testing.T) {
	for _, c := range loadFaultCases(t) {
		for _, op := range c.Ops {
			c, op := c, op
			t.Run(fmt.Sprintf("%s: %s -> %s", c.Fault, opNames[op], c.Expect), func(t *testing.T) {
				if defect, ok := knownDefects[c.Fault+":"+string(op)]; ok {
					t.Skip(defect)
				}
				current = t
				postFault(t, "/_reset")
				client := newClient(t, clientOptions{base: faultURL()})
				postFault(t, "/_arm?fault="+c.Fault)
				ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
				defer cancel()
				result, err := callFault(ctx, client, op)
				if errors.Is(ctx.Err(), context.DeadlineExceeded) {
					t.Fatalf("%s hung for 8 seconds", c.Fault)
				}
				if c.Expect == "value" && err != nil {
					t.Fatalf("unexpected failure: %v", err)
				}
				if c.Expect == "failure" && err == nil {
					t.Fatalf("decoded without a failure: %v", result)
				}
				assertHealthy(context.Background(), t, client, op)
			})
		}
	}
}

func TestFaultRestErrorCarriesTheStatusAndTheBodyOfAGatewayPage(t *testing.T) {
	current = t
	postFault(t, "/_reset")
	client := newClient(t, clientOptions{base: faultURL()})
	postFault(t, "/_arm?fault=html-502")
	_, err := client.Queries.Count(context.Background())
	var rest *generated.RestError
	if !errors.As(err, &rest) || rest.Status != 502 || !strings.Contains(rest.Body, "Bad Gateway") {
		t.Fatalf("expected a RestError 502 with the page body, got %v", err)
	}
}

func TestFaultGraphQLErrorReachesTheCallerWithMessagePathAndExtensions(t *testing.T) {
	current = t
	postFault(t, "/_reset")
	client := newClient(t, clientOptions{base: faultURL()})
	postFault(t, "/_arm?fault=gql-errors-only")
	_, err := client.Queries.GetCount(context.Background())
	var exception *generated.GraphLinkException
	if !errors.As(err, &exception) || len(exception.Errors) != 1 {
		t.Fatalf("expected one GraphQL error, got %v", err)
	}
	first := exception.Errors[0]
	if first.Message != "boom" || len(first.Path) != 1 || first.Path[0] != "getCount" || first.Extensions["code"] != "BAD" {
		t.Fatalf("error lost its details: %+v", first)
	}
}

func TestFaultGraphQLCallKeepsTheHTTPStatusAndBody(t *testing.T) {
	for fault, want := range map[string][2]any{"html-502": {502, "Bad Gateway"}, "status-401-json": {401, "unauthorized"}} {
		current = t
		postFault(t, "/_reset")
		client := newClient(t, clientOptions{base: faultURL()})
		postFault(t, "/_arm?fault="+fault)
		_, err := client.Queries.GetCount(context.Background())
		var exception *generated.GraphLinkException
		if !errors.As(err, &exception) || len(exception.Errors) != 1 {
			t.Fatalf("%s: expected one GraphQL error, got %v", fault, err)
		}
		first := exception.Errors[0]
		if first.Status == nil || *first.Status != want[0].(int) || first.Body == nil || !strings.Contains(*first.Body, want[1].(string)) {
			t.Fatalf("%s: status and body lost: %+v", fault, first)
		}
	}
}

func TestFaultResponseWithoutDataAndWithoutErrorsSaysSo(t *testing.T) {
	current = t
	postFault(t, "/_reset")
	client := newClient(t, clientOptions{base: faultURL()})
	postFault(t, "/_arm?fault=gql-empty-object")
	_, err := client.Queries.GetCount(context.Background())
	if err == nil || !strings.Contains(err.Error(), "no data") {
		t.Fatalf("expected a no-data error, got %v", err)
	}
}
