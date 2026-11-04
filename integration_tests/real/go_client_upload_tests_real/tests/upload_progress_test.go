package tests

import (
	"io"
	"os"
	"sync/atomic"
	"testing"
	"time"

	gl "graphlink.dev/uploadtests/generated"
)

func pattern(size int) []byte {
	data := make([]byte, size)
	for i := range data {
		data[i] = byte((i*31 + 7) % 251)
	}
	return data
}

func newClient(t *testing.T, url string) *gl.GraphLinkClient {
	t.Helper()
	client, err := gl.NewGraphLinkClientWithHttp(gl.GraphLinkHttpOptions{URL: url})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func known(data []byte, name string) gl.GLUpload { return gl.GLUploadFromBytes(data, name, "") }

type chunkReader struct {
	data   []byte
	offset int
	pulled *int64
	pause  bool
}

func (r *chunkReader) Read(buffer []byte) (int, error) {
	if r.offset >= len(r.data) {
		return 0, io.EOF
	}
	if r.pause && r.offset%(256*1024) == 0 {
		time.Sleep(2 * time.Millisecond)
	}
	n := copy(buffer, r.data[r.offset:min(r.offset+65536, len(r.data))])
	r.offset += n
	if r.pulled != nil {
		atomic.StoreInt64(r.pulled, int64(r.offset))
	}
	return n, nil
}

func unknown(data []byte, name string) gl.GLUpload {
	return gl.GLUpload{Reader: &chunkReader{data: data}, Length: -1, Filename: name, MimeType: "application/octet-stream"}
}

func TestA6MBFileArrivesIntactWithoutProgress(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(6 * 1024 * 1024)
	res, err := newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", known(data, "big.bin"))
	if err != nil || !res.UploadOneFile {
		t.Fatalf("upload failed: %v", err)
	}
	sent := server.only(t)
	if sent.part("0").sha() != shaOf(data) || sent.part("0").Filename != "big.bin" {
		t.Fatal("file did not arrive intact")
	}
}

func TestAFileOfKnownLengthIsSentWithAContentLength(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(300000)
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", known(data, "a.bin")))
	sent := server.only(t)
	if sent.Chunked || sent.ContentLength <= int64(len(data)) {
		t.Fatalf("expected a content length, got chunked=%v length=%d", sent.Chunked, sent.ContentLength)
	}
}

func TestAFileOfUnknownLengthArrivesIntactSentChunked(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(300000)
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", unknown(data, "a.bin")))
	sent := server.only(t)
	if sent.part("0").sha() != shaOf(data) || !sent.Chunked {
		t.Fatalf("expected an intact chunked upload, chunked=%v", sent.Chunked)
	}
}

func TestA6MBFileArrivesIntactWithProgress(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(6 * 1024 * 1024)
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", known(data, "big.bin"),
		gl.UploadOneFileOptions{OnProgress: func(sent, total int64) {}}))
	if server.only(t).part("0").sha() != shaOf(data) {
		t.Fatal("file did not arrive intact")
	}
}

func TestProgressIncreasesAndEndsAtTheTotal(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(6 * 1024 * 1024)
	var reports [][2]int64
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", known(data, "big.bin"),
		gl.UploadOneFileOptions{OnProgress: func(sent, total int64) { reports = append(reports, [2]int64{sent, total}) }}))
	if len(reports) <= 10 {
		t.Fatalf("expected many progress reports, got %d", len(reports))
	}
	for i := 1; i < len(reports); i++ {
		if reports[i][0] < reports[i-1][0] {
			t.Fatal("progress went backwards")
		}
	}
	last := reports[len(reports)-1]
	if last[0] != last[1] || last[1] <= int64(len(data)) || last[1] != server.only(t).ContentLength {
		t.Fatalf("progress did not end at the content length: %v", last)
	}
}

func TestTheFileIsNotReadInFullBeforeTheFirstProgressReport(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(6 * 1024 * 1024)
	var pulled int64
	atFirstReport := int64(-1)
	file := gl.GLUpload{Reader: &chunkReader{data: data, pulled: &pulled, pause: true}, Length: int64(len(data)), Filename: "big.bin", MimeType: "application/octet-stream"}
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", file,
		gl.UploadOneFileOptions{OnProgress: func(sent, total int64) {
			if atFirstReport < 0 {
				atFirstReport = atomic.LoadInt64(&pulled)
			}
		}}))
	if atFirstReport < 0 || atFirstReport >= int64(len(data)) {
		t.Fatalf("read %d of %d bytes before the first progress report", atFirstReport, len(data))
	}
}

func TestAFileOfUnknownLengthFiresNoProgressAndArrivesIntact(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(300000)
	calls := 0
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", unknown(data, "a.bin"),
		gl.UploadOneFileOptions{OnProgress: func(sent, total int64) { calls++ }}))
	sent := server.only(t)
	if sent.part("0").sha() != shaOf(data) || !sent.Chunked || calls != 0 {
		t.Fatalf("expected an intact chunked upload with no progress, chunked=%v calls=%d", sent.Chunked, calls)
	}
}

func TestTwoFilesArriveIntactInSlotOrderWithProgress(t *testing.T) {
	server := newRecordingServer(t)
	first := pattern(1200000)
	second := pattern(900000)
	for i, j := 0, len(second)-1; i < j; i, j = i+1, j-1 {
		second[i], second[j] = second[j], second[i]
	}
	var last [2]int64
	res := must(newClient(t, server.URL).Mutations.UploadFileList(ctx(t), "u1", []gl.GLUpload{known(first, "a.bin"), known(second, "b.bin")},
		gl.UploadFileListOptions{OnProgress: func(sent, total int64) { last = [2]int64{sent, total} }}))
	if !res.UploadFileList {
		t.Fatal("expected true")
	}
	sent := server.only(t)
	if sent.part("0").sha() != shaOf(first) || sent.part("0").Filename != "a.bin" ||
		sent.part("1").sha() != shaOf(second) || sent.part("1").Filename != "b.bin" {
		t.Fatal("files did not arrive intact in slot order")
	}
	if last[0] != last[1] {
		t.Fatalf("progress did not end at the total: %v", last)
	}
}

func TestAFileFromDiskIsStreamedWithItsLength(t *testing.T) {
	server := newRecordingServer(t)
	data := pattern(500000)
	path := t.TempDir() + "/disk.bin"
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	file, err := gl.GLUploadFromFile(path, "")
	if err != nil {
		t.Fatal(err)
	}
	must(newClient(t, server.URL).Mutations.UploadOneFile(ctx(t), "u1", file))
	sent := server.only(t)
	if sent.part("0").sha() != shaOf(data) || sent.part("0").Filename != "disk.bin" || sent.Chunked {
		t.Fatal("file from disk did not arrive intact with a content length")
	}
}
