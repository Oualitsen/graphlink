package tests

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sync"

	gl "graphlink.dev/persistedmock/generated"
)

type NoWebSocketAdapter struct{}

func (NoWebSocketAdapter) Connect(ctx context.Context) error                     { return nil }
func (NoWebSocketAdapter) SendMessage(ctx context.Context, message string) error { return nil }
func (NoWebSocketAdapter) Close() error                                          { return nil }
func (NoWebSocketAdapter) ConnectionInitPayload(ctx context.Context) (map[string]any, error) {
	return nil, nil
}
func (NoWebSocketAdapter) SetMessageHandler(handler func(message string)) {}
func (NoWebSocketAdapter) SetReconnectHandler(handler func())             {}

func sha256Hex(text string) string {
	sum := sha256.Sum256([]byte(text))
	return hex.EncodeToString(sum[:])
}

// ApqServer behaves like an Apollo-style APQ server in front of canned responses.
type ApqServer struct {
	mu              sync.Mutex
	responses       map[string]any
	registered      map[string]bool
	Requests        []map[string]any
	Methods         []string
	Supported       bool
	NotFoundMessage string
	GetSupported    bool
	FailWith        error
	GetFailWith     error
}

func NewApqServer() *ApqServer {
	return &ApqServer{
		responses:       map[string]any{},
		registered:      map[string]bool{},
		Supported:       true,
		NotFoundMessage: "PersistedQueryNotFound",
		GetSupported:    true,
	}
}

func (s *ApqServer) RespondTo(operation string, data map[string]any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.responses[operation] = map[string]any{"data": data}
}

func (s *ApqServer) RespondWithErrors(operation string, errs ...map[string]any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.responses[operation] = map[string]any{"data": nil, "errors": errs}
}

func (s *ApqServer) Evict() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.registered = map[string]bool{}
}

func (s *ApqServer) ClearRecords() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Requests = nil
	s.Methods = nil
}

func IsHashOnly(body map[string]any) bool {
	_, hasExtensions := body["extensions"]
	_, hasQuery := body["query"]
	return hasExtensions && !hasQuery
}

func (s *ApqServer) Call(ctx context.Context, payload string) (string, error) {
	s.mu.Lock()
	s.Methods = append(s.Methods, "POST")
	failure := s.FailWith
	s.mu.Unlock()
	return s.handle(payload, failure)
}

func (s *ApqServer) Get(ctx context.Context, payload string) (string, error) {
	s.mu.Lock()
	s.Methods = append(s.Methods, "GET")
	supported := s.GetSupported
	failure := s.GetFailWith
	s.mu.Unlock()
	if !supported {
		return "", &gl.GraphLinkGetNotSupported{Message: "GET is not allowed"}
	}
	return s.handle(payload, failure)
}

func (s *ApqServer) handle(payload string, failure error) (string, error) {
	var body map[string]any
	if err := json.Unmarshal([]byte(payload), &body); err != nil {
		return "", err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Requests = append(s.Requests, body)
	if failure != nil {
		return "", failure
	}
	if extensions, ok := body["extensions"].(map[string]any); ok {
		if persisted, ok := extensions["persistedQuery"].(map[string]any); ok {
			if !s.Supported {
				return apqError("PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED"), nil
			}
			hash := persisted["sha256Hash"].(string)
			if query, hasQuery := body["query"].(string); !hasQuery {
				if !s.registered[hash] {
					return apqError(s.NotFoundMessage, "PERSISTED_QUERY_NOT_FOUND"), nil
				}
			} else {
				if sha256Hex(query) != hash {
					return apqError("provided sha does not match query", "INTERNAL_SERVER_ERROR"), nil
				}
				s.registered[hash] = true
			}
		}
	}
	operation, _ := body["operationName"].(string)
	response, ok := s.responses[operation]
	if !ok {
		return "", errors.New(fmt.Sprintf("No response registered for %s", operation))
	}
	encoded, err := json.Marshal(response)
	return string(encoded), err
}

func apqError(message, code string) string {
	encoded, _ := json.Marshal(map[string]any{
		"errors": []any{map[string]any{"message": message, "extensions": map[string]any{"code": code}}},
	})
	return string(encoded)
}
