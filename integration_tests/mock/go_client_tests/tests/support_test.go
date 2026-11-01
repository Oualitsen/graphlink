package tests

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sync"
	"testing"
	"time"

	gl "graphlink.dev/mocktests/generated"
)

var operationPattern = regexp.MustCompile(`(?:query|mutation|subscription)\s+(\w+)`)

func parseOperationName(query string) string {
	match := operationPattern.FindStringSubmatch(query)
	if match == nil {
		return ""
	}
	return match[1]
}

type RecordedCall struct {
	OperationName string
	Query         string
	Variables     map[string]any
	RawPayload    string
}

// MockAdapter returns pre-registered responses and records every request.
type MockAdapter struct {
	mu              sync.Mutex
	responses       map[string]string
	calls           []RecordedCall
	SimulateFailure bool
}

func NewMockAdapter() *MockAdapter {
	return &MockAdapter{responses: map[string]string{}}
}

func (m *MockAdapter) Register(operation, response string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.responses[operation] = response
}

func (m *MockAdapter) RegisterData(operation string, data map[string]any) {
	m.Register(operation, mustJSON(map[string]any{"data": data}))
}

func (m *MockAdapter) RegisterErrors(operation string, errs ...map[string]any) {
	m.Register(operation, mustJSON(map[string]any{"data": nil, "errors": errs}))
}

func (m *MockAdapter) CallCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.calls)
}

func (m *MockAdapter) LastCall() RecordedCall {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.calls[len(m.calls)-1]
}

func (m *MockAdapter) Call(ctx context.Context, payload string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.SimulateFailure {
		return "", errors.New("Simulated network failure")
	}
	var decoded struct {
		Query     string         `json:"query"`
		Variables map[string]any `json:"variables"`
	}
	if err := json.Unmarshal([]byte(payload), &decoded); err != nil {
		return "", err
	}
	name := parseOperationName(decoded.Query)
	m.calls = append(m.calls, RecordedCall{OperationName: name, Query: decoded.Query, Variables: decoded.Variables, RawPayload: payload})
	if response, ok := m.responses[name]; ok {
		return response, nil
	}
	return "", fmt.Errorf("MockAdapter: no response registered for %q", name)
}

// MockMultipartAdapter records the multipart parts of upload mutations.
type MockMultipartAdapter struct {
	mu        sync.Mutex
	responses map[string]string
	calls     []map[string]any
}

func NewMockMultipartAdapter() *MockMultipartAdapter {
	return &MockMultipartAdapter{responses: map[string]string{}}
}

func (m *MockMultipartAdapter) RegisterData(operation string, data map[string]any) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.responses[operation] = mustJSON(map[string]any{"data": data})
}

func (m *MockMultipartAdapter) CallCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.calls)
}

func (m *MockMultipartAdapter) LastCall() map[string]any {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.calls[len(m.calls)-1]
}

func (m *MockMultipartAdapter) Call(ctx context.Context, parts map[string]any, onProgress gl.UploadProgressCallback) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	copied := make(map[string]any, len(parts))
	for key, value := range parts {
		copied[key] = value
	}
	m.calls = append(m.calls, copied)
	var operations struct {
		Query string `json:"query"`
	}
	if err := json.Unmarshal([]byte(parts["operations"].(string)), &operations); err != nil {
		return "", err
	}
	name := parseOperationName(operations.Query)
	if response, ok := m.responses[name]; ok {
		return response, nil
	}
	return "", fmt.Errorf("MockMultipartAdapter: no response registered for %q", name)
}

// MockWebSocketAdapter completes the graphql-transport-ws handshake by itself.
type MockWebSocketAdapter struct {
	mu             sync.Mutex
	onMessage      func(string)
	onReconnect    func()
	sent           []map[string]any
	subscriptionID string
	ready          chan struct{}
	readyOnce      sync.Once
}

func NewMockWebSocketAdapter() *MockWebSocketAdapter {
	return &MockWebSocketAdapter{ready: make(chan struct{})}
}

func (m *MockWebSocketAdapter) Connect(ctx context.Context) error { return nil }
func (m *MockWebSocketAdapter) Close() error                       { return nil }
func (m *MockWebSocketAdapter) ConnectionInitPayload(ctx context.Context) (map[string]any, error) {
	return nil, nil
}

func (m *MockWebSocketAdapter) SetMessageHandler(handler func(string)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onMessage = handler
}

func (m *MockWebSocketAdapter) SetReconnectHandler(handler func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onReconnect = handler
}

func (m *MockWebSocketAdapter) SendMessage(ctx context.Context, message string) error {
	var decoded map[string]any
	if err := json.Unmarshal([]byte(message), &decoded); err != nil {
		return err
	}
	m.mu.Lock()
	m.sent = append(m.sent, decoded)
	handler := m.onMessage
	kind, _ := decoded["type"].(string)
	if kind == "subscribe" {
		m.subscriptionID, _ = decoded["id"].(string)
	}
	m.mu.Unlock()
	switch kind {
	case "connection_init":
		go handler(mustJSON(map[string]any{"type": "connection_ack"}))
	case "subscribe":
		m.readyOnce.Do(func() { close(m.ready) })
	}
	return nil
}

func (m *MockWebSocketAdapter) SentMessages() []map[string]any {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]map[string]any(nil), m.sent...)
}

func (m *MockWebSocketAdapter) WaitSubscriptionReady(t *testing.T) {
	t.Helper()
	select {
	case <-m.ready:
	case <-time.After(5 * time.Second):
		t.Fatal("subscription was never subscribed")
	}
}

func (m *MockWebSocketAdapter) push(message map[string]any) {
	m.mu.Lock()
	handler := m.onMessage
	message["id"] = m.subscriptionID
	m.mu.Unlock()
	handler(mustJSON(message))
}

func (m *MockWebSocketAdapter) PushEvent(data map[string]any) {
	m.push(map[string]any{"type": "next", "payload": map[string]any{"data": data}})
}

func (m *MockWebSocketAdapter) PushComplete() {
	m.push(map[string]any{"type": "complete"})
}

func mustJSON(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return string(encoded)
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

type harness struct {
	adapter   *MockAdapter
	multipart *MockMultipartAdapter
	ws        *MockWebSocketAdapter
	client    *gl.GraphLinkClient
	ctx       context.Context
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	h := &harness{adapter: NewMockAdapter(), multipart: NewMockMultipartAdapter(), ws: NewMockWebSocketAdapter()}
	var cancel context.CancelFunc
	h.ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{
		Adapter:       h.adapter.Call,
		UploadAdapter: h.multipart.Call,
		WsAdapter:     h.ws,
	})
	if err != nil {
		t.Fatal(err)
	}
	h.client = client
	return h
}

func firstEvent[T any](t *testing.T, events <-chan gl.GraphLinkEvent[T]) gl.GraphLinkEvent[T] {
	t.Helper()
	select {
	case event, ok := <-events:
		if !ok {
			t.Fatal("subscription closed before an event arrived")
		}
		return event
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for subscription event")
	}
	return gl.GraphLinkEvent[T]{}
}

func merge(base map[string]any, overrides map[string]any) map[string]any {
	result := make(map[string]any, len(base)+len(overrides))
	for k, v := range base {
		result[k] = v
	}
	for k, v := range overrides {
		result[k] = v
	}
	return result
}

type list = []any
type object = map[string]any

var (
	addressJson        = object{"street": "123 Main St", "city": "Springfield", "country": "US", "zip": "12345"}
	addressNoZipJson   = object{"street": "456 Oak Ave", "city": "Shelbyville", "country": "US", "zip": nil}
	billingAddressJson = object{"street": "789 Pine Rd", "city": "Capital City", "country": "US", "zip": "99999"}

	userAliceJson = object{
		"id": "user-1", "name": "Alice Smith", "email": "alice@test.com", "status": "ACTIVE", "priority": "HIGH",
		"address": addressJson, "billingAddress": nil, "tags": list{"admin", "beta"}, "scores": list{10, 20, 30},
	}
	userBobJson = object{
		"id": "user-2", "name": "Bob Jones", "email": "bob@test.com", "status": "INACTIVE", "priority": nil,
		"address": addressNoZipJson, "billingAddress": billingAddressJson, "tags": list{}, "scores": nil,
	}

	allScalarsNullJson = object{
		"id": "scalar-1", "strVal": "hello world", "intVal": 42, "floatVal": 3.14, "boolVal": true,
		"nullableStr": nil, "nullableInt": nil, "nullableFloat": nil, "nullableBool": nil, "nullableId": nil,
	}
	allScalarsPresentJson = object{
		"id": "scalar-2", "strVal": "edge case", "intVal": -1, "floatVal": -0.5, "boolVal": false,
		"nullableStr": "present", "nullableInt": 99, "nullableFloat": 2.718, "nullableBool": false, "nullableId": "nid-1",
	}

	postJson = object{
		"id": "post-1", "title": "Hello World", "body": "Post body text.", "author": userAliceJson,
		"coAuthor": nil, "viewCount": 128,
	}
	postWithCoAuthorJson = object{
		"id": "post-2", "title": "Collaboration", "body": "Written together.", "author": userAliceJson,
		"coAuthor": userBobJson, "viewCount": 42,
	}

	auditEntryWithExtraJson = object{
		"id": "audit-2", "action": "LOGOUT", "performedBy": "user-1", "internalNote": "this should be silently ignored",
	}

	postWithAuthorCycleJson = object{
		"id": "post-10", "title": "Cyclic Post", "body": "Body text.",
		"author": object{
			"id": "user-1", "name": "Alice Smith", "email": "alice@test.com", "status": "ACTIVE", "priority": "HIGH",
			"address": addressJson, "billingAddress": nil, "tags": list{"admin"}, "scores": nil, "posts": nil,
		},
		"coAuthor": nil, "viewCount": 7,
	}
	userWithPostsJson = merge(userAliceJson, object{"posts": list{postWithAuthorCycleJson}})

	tagsJson = list{
		object{"id": "tag-1", "label": "dart", "color": "#0175C2"},
		object{"id": "tag-2", "label": "graphql", "color": nil},
	}

	graphQLError = object{
		"message": "Not found", "locations": list{object{"line": 1, "column": 1}}, "path": list{"getUser"},
	}
)

func minimalInput() gl.CreateUserInput {
	return gl.CreateUserInput{
		Name: "Alice Smith", Email: "alice@test.com", Status: gl.UserStatusActive,
		Address: gl.AddressInput{Street: "123 Main St", City: "Springfield", Country: "US"},
	}
}

func expectEqual[T comparable](t *testing.T, got, want T, what string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: got %v, want %v", what, got, want)
	}
}
