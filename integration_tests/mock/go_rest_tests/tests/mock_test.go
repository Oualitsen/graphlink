package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"graphlink.dev/restmocks/generated"
)

type spec struct {
	status  int
	body    string
	headers map[string]string
}

type mockRest struct {
	mu            sync.Mutex
	calls         []generated.RestRequest
	bodies        []string
	specs         map[string]spec
	failTransport bool
}

func newMock() *mockRest { return &mockRest{specs: map[string]spec{}} }

func (m *mockRest) on(method, path string, status int, body string, headers ...map[string]string) {
	s := spec{status: status, body: body}
	if len(headers) > 0 {
		s.headers = headers[0]
	}
	m.specs[method+" "+path] = s
}

func (m *mockRest) json(method, path string, value any) {
	encoded, _ := json.Marshal(value)
	m.on(method, path, 200, string(encoded))
}

func (m *mockRest) last() generated.RestRequest { return m.calls[len(m.calls)-1] }

func (m *mockRest) call(ctx context.Context, request generated.RestRequest) (*generated.RestResponse, error) {
	if m.failTransport {
		return nil, io.ErrUnexpectedEOF
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls = append(m.calls, request)
	switch body := request.Body.(type) {
	case generated.RestJSONBody:
		m.bodies = append(m.bodies, string(body.JSON))
	case generated.RestRawBody:
		data, _ := io.ReadAll(body.Upload.Reader)
		m.bodies = append(m.bodies, string(data))
	}
	s, ok := m.specs[request.Method+" "+request.Path]
	if !ok {
		return generated.NewRestResponse(404, []byte("no mock"), nil), nil
	}
	return generated.NewRestResponse(s.status, []byte(s.body), s.headers), nil
}

func setup(t *testing.T) (context.Context, *mockRest, *generated.GraphLinkClient) {
	t.Helper()
	current = t
	m := newMock()
	client, err := generated.NewGraphLinkClient(generated.GraphLinkClientOptions{
		Adapter: func(ctx context.Context, payload string) (string, error) {
			return `{"data":{"ping":"pong"}}`, nil
		},
		RestAdapter: m.call,
	})
	if err != nil {
		t.Fatal(err)
	}
	return context.Background(), m, client
}

var current *testing.T

func must[T any](v T, err error) T {
	current.Helper()
	if err != nil {
		current.Fatalf("unexpected error: %v", err)
	}
	return v
}

func eq(t *testing.T, actual, expected any) {
	t.Helper()
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("expected %#v, got %#v", expected, actual)
	}
}

func query(r generated.RestRequest) string {
	parts := make([]string, len(r.Query))
	for i, e := range r.Query {
		parts[i] = e.Name + "=" + e.Value
	}
	return strings.Join(parts, "&")
}

func sp(s string) *string { return &s }

var product = map[string]any{"id": "p1", "name": "Pen", "price": 2.5, "status": "ACTIVE", "tags": []string{"a", "b"}}

func TestRequests(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.json("GET", "/products/a%20b", product)
	archived := generated.StatusArchived
	result := must(client.Queries.Product(ctx, "a b", generated.ProductOptions{Status: &archived}))
	eq(t, result.Name, "Pen")
	eq(t, rest.last().Method, "GET")
	eq(t, query(rest.last()), "status=ARCHIVED")
	eq(t, rest.last().Headers["Accept"], "application/json")
	if rest.last().Body != nil || rest.last().Headers["Content-Type"] != "" {
		t.Fatal("a GET sends no body and no Content-Type")
	}

	rest.json("GET", "/products", []any{product})
	must(client.Queries.Products(ctx, generated.ProductsOptions{
		Filter: &generated.Filter{Tag: sp("x"), MinPrice: generated.Ptr(3.0)},
		Ids:    []string{"1", "2"},
		Auth:   &generated.Auth{Token: sp("t"), RequestId: sp("r1")},
	}))
	eq(t, query(rest.last()), "tag=x&minPrice=3&page=1&ids=1&ids=2")
	eq(t, rest.last().Headers["token"], "t")
	eq(t, rest.last().Headers["X-Request-Id"], "r1")

	must(client.Queries.Products(ctx))
	eq(t, query(rest.last()), "page=1")
}

func TestFlatListObjectsAndBodies(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.json("GET", "/products/search", map[string]any{"data": map[string]any{"total": 1, "items": []any{product}}})
	page := must(client.Queries.Search(ctx, "pen", generated.SearchOptions{
		Groups: []generated.Group{{Name: "g", Ids: []int{1, 2}}, {Name: "h"}},
		Tags:   []string{"x", "y"},
	}))
	eq(t, query(rest.last()), "q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y")
	eq(t, page.Total, 1)
	eq(t, page.Items[0].Id, "p1")

	rest.on("POST", "/products", 201, mustJSON(product))
	created := must(client.Mutations.CreateProduct(ctx, generated.ProductIn{Name: "Pen", Price: generated.Ptr(2.5)}))
	eq(t, created.Id, "p1")
	var decoded map[string]any
	_ = json.Unmarshal([]byte(rest.bodies[0]), &decoded)
	eq(t, decoded["name"], "Pen")
	eq(t, rest.last().Headers["Content-Type"], "application/json")

	rest.json("POST", "/products/p1/rename", product)
	must(client.Mutations.Rename(ctx, "p1", "New"))
	form := rest.last().Body.(generated.RestFormBody)
	eq(t, form.Fields, []generated.RestEntry{{Name: "name", Value: "New"}})
	eq(t, rest.last().Headers["Content-Type"], "application/x-www-form-urlencoded")

	rest.json("POST", "/products/p1/gallery", product)
	must(client.Mutations.Gallery(ctx, "p1", []generated.GLUpload{
		generated.GLUploadFromBytes([]byte("1"), "a.png", ""), generated.GLUploadFromBytes([]byte("2"), "b.png", ""),
	}, generated.GalleryOptions{Title: sp("T")}))
	multipart := rest.last().Body.(generated.RestMultipartBody)
	names := []string{}
	for _, p := range multipart.Parts {
		names = append(names, p.Name)
	}
	eq(t, names, []string{"title", "files", "files"})
	eq(t, multipart.Parts[0].Value, "T")
	eq(t, multipart.Parts[2].File.Filename, "b.png")
	eq(t, rest.last().Headers["Content-Type"], "")

	rest.on("PUT", "/products/p1/avatar", 204, "")
	if err := client.Mutations.Avatar(ctx, "p1", generated.GLUploadFromBytes([]byte("bytes"), "", "image/png")); err != nil {
		t.Fatal(err)
	}
	eq(t, rest.bodies[len(rest.bodies)-1], "bytes")
	eq(t, rest.last().Headers["Content-Type"], "image/png")
}

func mustJSON(v any) string {
	encoded, _ := json.Marshal(v)
	return string(encoded)
}

func TestResponses(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.on("DELETE", "/products/p1", 200, "whatever")
	if err := client.Mutations.DeleteProduct(ctx, "p1"); err != nil {
		t.Fatal(err)
	}
	rest.on("GET", "/products/p1", 204, "")
	if got := must(client.Queries.Product(ctx, "p1")); got != nil {
		t.Fatal("a nullable empty result is nil")
	}
	rest.on("GET", "/products/count", 200, "")
	if _, err := client.Queries.Count(ctx); err == nil || !strings.Contains(err.Error(), "Empty REST response") {
		t.Fatalf("expected an empty-response error, got %v", err)
	}
	rest.on("GET", "/products/p1", 404, "nope", map[string]string{"x-a": "b"})
	_, err := client.Queries.Product(ctx, "p1")
	restErr, ok := err.(*generated.RestError)
	if !ok {
		t.Fatalf("expected RestError, got %v", err)
	}
	eq(t, []any{restErr.Status, restErr.Body, restErr.Headers["x-a"]}, []any{404, "nope", "b"})

	rest.on("GET", "/products/p1/note", 200, "hello")
	note := must(client.Queries.Note(ctx, "p1"))
	eq(t, *note, "hello")
	rest.json("GET", "/products/count", 7)
	eq(t, must(client.Queries.Count(ctx)), 7)

	ping := must(client.Queries.Ping(ctx))
	eq(t, *ping.Ping, "pong")
}

func TestCache(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.json("GET", "/products/cached/p1", product)
	must(client.Queries.Cached(ctx, "p1"))
	must(client.Queries.Cached(ctx, "p1"))
	eq(t, len(rest.calls), 1)
	rest.json("GET", "/products/cached/p2", product)
	must(client.Queries.Cached(ctx, "p2"))
	eq(t, len(rest.calls), 2)

	gets := func() int {
		n := 0
		for _, c := range rest.calls {
			if c.Method == "GET" {
				n++
			}
		}
		return n
	}
	before := gets()
	rest.json("PUT", "/products/cached/p1", product)
	must(client.Mutations.UpdateCached(ctx, "p1", generated.ProductIn{Name: "x"}))
	must(client.Queries.Cached(ctx, "p1"))
	eq(t, gets(), before+1)

	rest.on("PUT", "/products/cached/p1", 500, "boom")
	if _, err := client.Mutations.UpdateCached(ctx, "p1", generated.ProductIn{Name: "x"}); err == nil {
		t.Fatal("expected a failure")
	}
	before = gets()
	must(client.Queries.Cached(ctx, "p1"))
	eq(t, gets(), before)
}

func TestStaleIfOffline(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.json("GET", "/products/offline/p1", product)
	must(client.Queries.CachedOffline(ctx, "p1"))
	time.Sleep(1100 * time.Millisecond)
	rest.failTransport = true
	eq(t, must(client.Queries.CachedOffline(ctx, "p1")).Id, "p1")
	rest.failTransport = false
	rest.on("GET", "/products/offline/p1", 500, "down")
	if _, err := client.Queries.CachedOffline(ctx, "p1"); err == nil {
		t.Fatal("a RestError is a response and is never masked")
	}
}

func TestDownloads(t *testing.T) {
	ctx, rest, client := setup(t)
	rest.on("GET", "/products/p1/export", 200, "abcdef", map[string]string{
		"content-type": "text/csv", "content-length": "6", "content-disposition": `attachment; filename="p 1.csv"`,
	})
	var received int64
	d := must(client.Queries.Export(ctx, "p1", generated.ExportOptions{OnReceiveProgress: func(r, total int64) { received = r*100 + total }}))
	eq(t, []any{d.Filename, d.ContentType, d.Length}, []any{"p 1.csv", "text/csv", int64(6)})
	eq(t, rest.last().Headers["Accept"], "*/*")
	eq(t, string(must(d.Bytes())), "abcdef")
	eq(t, received, int64(606))

	rest.on("GET", "/products/p1/export", 200, "x", map[string]string{"content-disposition": "attachment; filename*=UTF-8''p%201%C3%A9.csv"})
	eq(t, must(client.Queries.Export(ctx, "p1")).Filename, "p 1é.csv")

	rest.on("GET", "/products/p1/maybe", 204, "")
	if got := must(client.Queries.MaybeExport(ctx, "p1")); got != nil {
		t.Fatal("a nullable download is nil on 204")
	}
	rest.on("GET", "/products/p1/export", 204, "")
	if _, err := client.Queries.Export(ctx, "p1"); err == nil || !strings.Contains(err.Error(), "Empty REST response") {
		t.Fatalf("expected an empty-response error, got %v", err)
	}
	rest.on("GET", "/products/p1/export", 500, "x")
	if _, err := client.Queries.Export(ctx, "p1"); err == nil {
		t.Fatal("expected RestError")
	}
}

var _ = http.StatusOK
