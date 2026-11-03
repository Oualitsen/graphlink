package tests

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"sync"
	"testing"
)

func shaOf(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

type receivedPart struct {
	Name, Filename string
	Data           []byte
}

func (p receivedPart) sha() string { return shaOf(p.Data) }

type received struct {
	ContentLength int64
	Chunked       bool
	Parts         []receivedPart
}

func (r received) part(name string) receivedPart {
	for _, part := range r.Parts {
		if part.Name == name {
			return part
		}
	}
	return receivedPart{}
}

// recordingServer is a GraphQL endpoint that records every multipart request as it arrived on the wire.
type recordingServer struct {
	*httptest.Server
	mu       sync.Mutex
	requests []received
}

func newRecordingServer(t *testing.T) *recordingServer {
	server := &recordingServer{}
	server.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		chunked := len(r.TransferEncoding) > 0 && r.TransferEncoding[0] == "chunked"
		var parts []receivedPart
		if match := regexp.MustCompile(`boundary=([^;]+)`).FindStringSubmatch(r.Header.Get("Content-Type")); match != nil {
			parts = parseMultipart(body, match[1])
		}
		server.mu.Lock()
		server.requests = append(server.requests, received{ContentLength: r.ContentLength, Chunked: chunked, Parts: parts})
		server.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":{"uploadOneFile":true,"uploadFileList":true}}`))
	}))
	t.Cleanup(server.Close)
	return server
}

func (s *recordingServer) only(t *testing.T) received {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.requests) != 1 {
		t.Fatalf("expected one request, got %d", len(s.requests))
	}
	return s.requests[0]
}

var dispositionPattern = regexp.MustCompile(`name="([^"]*)"(?:; filename="([^"]*)")?`)

func parseMultipart(body []byte, boundary string) []receivedPart {
	delimiter := []byte("--" + boundary)
	var starts []int
	for at := 0; ; {
		i := bytes.Index(body[at:], delimiter)
		if i < 0 {
			break
		}
		starts = append(starts, at+i)
		at += i + len(delimiter)
	}
	var parts []receivedPart
	for i := 0; i+1 < len(starts); i++ {
		from := starts[i] + len(delimiter) + 2
		to := starts[i+1] - 2
		headerEnd := from + bytes.Index(body[from:], []byte("\r\n\r\n"))
		match := dispositionPattern.FindSubmatch(body[from:headerEnd])
		parts = append(parts, receivedPart{Name: string(match[1]), Filename: string(match[2]), Data: body[headerEnd+4 : to]})
	}
	return parts
}
