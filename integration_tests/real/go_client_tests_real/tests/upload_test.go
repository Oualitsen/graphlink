package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func makeFile(name string, bytes ...byte) gl.GLUpload {
	return gl.GLUploadFromBytes(bytes, name, "image/png")
}

func TestUploadOneFile(t *testing.T) {
	c := newUploadClient(t)
	if !must(c.Mutations.UploadOneFile(ctx(t), "user-1", makeFile("test.png", 1, 2, 3))).UploadOneFile {
		t.Fatal("expected true")
	}
	if !must(c.Mutations.UploadOneFile(ctx(t), "user-42", makeFile("test.png", 10, 20, 30))).UploadOneFile {
		t.Fatal("expected true for another user")
	}
	big := make([]byte, 1024)
	for i := range big {
		big[i] = byte(i % 256)
	}
	if !must(c.Mutations.UploadOneFile(ctx(t), "user-1", makeFile("big.bin", big...))).UploadOneFile {
		t.Fatal("expected true for a larger file")
	}
}

func TestUploadFileList(t *testing.T) {
	c := newUploadClient(t)
	one := []gl.GLUpload{makeFile("test.png", 1, 2, 3)}
	if !must(c.Mutations.UploadFileList(ctx(t), "user-1", one)).UploadFileList {
		t.Fatal("expected true for one file")
	}
	two := []gl.GLUpload{makeFile("test.png", 1, 2, 3), makeFile("second.png", 4, 5, 6)}
	if !must(c.Mutations.UploadFileList(ctx(t), "user-1", two)).UploadFileList {
		t.Fatal("expected true for two files")
	}
	three := []gl.GLUpload{makeFile("a.png", 1), makeFile("b.png", 2), makeFile("c.png", 3)}
	if !must(c.Mutations.UploadFileList(ctx(t), "user-2", three)).UploadFileList {
		t.Fatal("expected true for three files")
	}
}

func TestUploadReportsProgress(t *testing.T) {
	c := newUploadClient(t)
	var lastSent, lastTotal int64
	calls := 0
	onProgress := func(sent, total int64) {
		calls++
		lastSent, lastTotal = sent, total
	}
	must(c.Mutations.UploadOneFile(ctx(t), "user-1", makeFile("test.png", 1, 2, 3), gl.UploadOneFileOptions{OnProgress: onProgress}))
	if calls == 0 || lastTotal == 0 || lastSent != lastTotal {
		t.Fatalf("calls=%d sent=%d total=%d", calls, lastSent, lastTotal)
	}
}
