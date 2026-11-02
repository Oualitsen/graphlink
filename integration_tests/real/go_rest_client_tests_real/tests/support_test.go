package tests

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"

	"graphlink.dev/resttests/generated"
)

var comma = os.Getenv("REST_VARIANT") == "comma"

func port() int {
	if comma {
		return 9982
	}
	return 9981
}

var serverURL = fmt.Sprintf("http://127.0.0.1:%d", port())

const deadURL = "http://127.0.0.1:1"

func key(base string, path ...string) string {
	for _, p := range path {
		if comma {
			base = base + "[" + p + "]"
		} else {
			base = base + "." + p
		}
	}
	return base
}

func list(name string, values ...string) []string {
	if comma {
		return []string{name + "=" + strings.Join(values, ",")}
	}
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = name + "=" + v
	}
	return out
}

type clientOptions struct {
	base    string
	headers func(ctx context.Context) (map[string]string, error)
	store   generated.GraphLinkCacheStore
}

func newClient(t *testing.T, opts ...clientOptions) *generated.GraphLinkClient {
	t.Helper()
	var o clientOptions
	if len(opts) > 0 {
		o = opts[0]
	}
	if o.base == "" {
		o.base = serverURL
	}
	client, err := generated.NewGraphLinkClientWithHttp(generated.GraphLinkHttpOptions{
		URL:             o.base + "/graphql",
		RestBaseURL:     o.base,
		HeadersProvider: o.headers,
		Store:           o.store,
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func setup(t *testing.T) (context.Context, *generated.GraphLinkClient) {
	t.Helper()
	current = t
	response, err := http.Post(serverURL+"/_reset", "text/plain", nil)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	return context.Background(), newClient(t)
}

var current *testing.T

func must[T any](value T, err error) T {
	current.Helper()
	if err != nil {
		current.Fatalf("unexpected error: %v", err)
	}
	return value
}

func mustOK(err error) {
	current.Helper()
	if err != nil {
		current.Fatalf("unexpected error: %v", err)
	}
}

func eq(t *testing.T, actual, expected any) {
	t.Helper()
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("expected %#v, got %#v", expected, actual)
	}
}

func isTrue(t *testing.T, condition bool, message string) {
	t.Helper()
	if !condition {
		t.Fatal(message)
	}
}

func restError(t *testing.T, err error) *generated.RestError {
	t.Helper()
	var restErr *generated.RestError
	if err == nil {
		t.Fatal("expected a RestError, got nil")
	}
	if !asRest(err, &restErr) {
		t.Fatalf("expected a RestError, got %T: %v", err, err)
	}
	return restErr
}

func asRest(err error, target **generated.RestError) bool {
	if e, ok := err.(*generated.RestError); ok {
		*target = e
		return true
	}
	return false
}

func notRest(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("expected an error")
	}
	if _, ok := err.(*generated.RestError); ok {
		t.Fatalf("expected a transport error, got RestError: %v", err)
	}
}

func pair(p generated.Pair) string { return p.Name + "=" + p.Value }

func pairs(items []generated.Pair) []string {
	out := make([]string, len(items))
	for i, p := range items {
		out[i] = pair(p)
	}
	return out
}

func sorted(values []string) []string {
	out := append([]string{}, values...)
	sort.Strings(out)
	return out
}

func queryValue(e generated.Echo, name string) (string, bool) {
	for _, p := range e.Query {
		if p.Name == name {
			return p.Value, true
		}
	}
	return "", false
}

func formValue(e generated.Echo, name string) string {
	for _, p := range e.Form {
		if p.Name == name {
			return p.Value
		}
	}
	return ""
}

func header(e generated.Echo, name string) (string, bool) {
	for _, h := range e.Headers {
		if h.Name == strings.ToLower(name) {
			return h.Value, true
		}
	}
	return "", false
}

func part(t *testing.T, e generated.Echo, name string) generated.Part {
	t.Helper()
	for _, p := range e.Parts {
		if p.Name == name {
			return p
		}
	}
	t.Fatalf("no part named %s", name)
	return generated.Part{}
}

func partsNamed(e generated.Echo, name string) []generated.Part {
	var out []generated.Part
	for _, p := range e.Parts {
		if p.Name == name {
			out = append(out, p)
		}
	}
	return out
}

func bodyJSON(t *testing.T, e generated.Echo) any {
	t.Helper()
	var value any
	text := ""
	if e.BodyText != nil {
		text = *e.BodyText
	}
	if err := json.Unmarshal([]byte(text), &value); err != nil {
		t.Fatalf("body is not JSON: %v", err)
	}
	return value
}

func pattern(size int) []byte {
	out := make([]byte, size)
	for i := range out {
		out[i] = byte(i % 251)
	}
	return out
}

func sha(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func upload(data []byte, filename, mimeType string) generated.GLUpload {
	return generated.GLUploadFromBytes(data, filename, mimeType)
}

func str(s string) *string { return &s }

func ptrString(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

var _ = bytes.NewReader
