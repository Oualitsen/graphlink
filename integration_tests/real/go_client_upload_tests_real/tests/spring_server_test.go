package tests

import (
	"os"
	"testing"

	gl "graphlink.dev/uploadtests/generated"
)

// The generated adapter against the Spring Boot upload server, which the recording server cannot stand in for.
func springClient(t *testing.T) *gl.GraphLinkClient {
	url := os.Getenv("UPLOAD_SERVER_URL")
	if url == "" {
		t.Skip("UPLOAD_SERVER_URL not set")
	}
	return newClient(t, url)
}

func TestSpringAcceptsAFileOfKnownLength(t *testing.T) {
	res := must(springClient(t).Mutations.UploadOneFile(ctx(t), "u1", known(pattern(3_000_000), "f.bin"),
		gl.UploadOneFileOptions{OnProgress: func(sent, total int64) {}}))
	if !res.UploadOneFile {
		t.Fatal("expected true")
	}
}

func TestSpringAcceptsAFileOfUnknownLengthChunked(t *testing.T) {
	if !must(springClient(t).Mutations.UploadOneFile(ctx(t), "u1", unknown(pattern(3_000_000), "f.bin"))).UploadOneFile {
		t.Fatal("expected true")
	}
}

func TestSpringAcceptsAListOfFiles(t *testing.T) {
	files := []gl.GLUpload{known(pattern(1000), "a.bin"), unknown(pattern(2000), "b.bin")}
	if !must(springClient(t).Mutations.UploadFileList(ctx(t), "u1", files)).UploadFileList {
		t.Fatal("expected true")
	}
}
