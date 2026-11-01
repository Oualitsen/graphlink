package tests

import (
	"encoding/json"
	"testing"

	gl "graphlink.dev/mocktests/generated"
)

func makeFile(bytes ...byte) gl.GLUpload {
	return gl.GLUploadFromBytes(bytes, "avatar.png", "image/png")
}

func decodeMap(t *testing.T, value any) map[string]any {
	t.Helper()
	var decoded map[string]any
	if err := json.Unmarshal([]byte(value.(string)), &decoded); err != nil {
		t.Fatal(err)
	}
	return decoded
}

func TestUploadOneFile(t *testing.T) {
	h := newHarness(t)
	h.multipart.RegisterData("uploadOneFile", object{"uploadOneFile": userAliceJson})
	res := must(h.client.Mutations.UploadOneFile(h.ctx, "user-42", makeFile(1, 2, 3)))
	expectEqual(t, res.UploadOneFile.Id, "user-1", "id")
	expectEqual(t, res.UploadOneFile.Name, "Alice Smith", "name")
	expectEqual(t, h.multipart.CallCount(), 1, "multipart calls")
	expectEqual(t, h.adapter.CallCount(), 0, "regular adapter calls")
	call := h.multipart.LastCall()
	variables := decodeMap(t, call["operations"])["variables"].(map[string]any)
	expectEqual(t, variables["userId"].(string), "user-42", "userId")
	if variables["file"] != nil {
		t.Fatalf("file variable should be null, got %v", variables["file"])
	}
	slots := decodeMap(t, call["map"])
	if got := slots["0"].([]any); len(got) != 1 || got[0] != "variables.file" {
		t.Fatalf("map slot 0: %v", got)
	}
	if _, ok := call["0"]; !ok {
		t.Fatal("file part missing under slot 0")
	}
}

func TestUploadFileList(t *testing.T) {
	h := newHarness(t)
	h.multipart.RegisterData("uploadFileList", object{"uploadFileList": userAliceJson})
	res := must(h.client.Mutations.UploadFileList(h.ctx, "user-1", []gl.GLUpload{makeFile(1, 2, 3), makeFile(4, 5, 6)}))
	expectEqual(t, res.UploadFileList.Id, "user-1", "id")
	call := h.multipart.LastCall()
	files := decodeMap(t, call["operations"])["variables"].(map[string]any)["files"].([]any)
	if len(files) != 2 || files[0] != nil || files[1] != nil {
		t.Fatalf("files variable: %v", files)
	}
	slots := decodeMap(t, call["map"])
	if got := slots["0"].([]any); got[0] != "variables.files.0" {
		t.Fatalf("map slot 0: %v", got)
	}
	if got := slots["1"].([]any); got[0] != "variables.files.1" {
		t.Fatalf("map slot 1: %v", got)
	}
	if _, ok := call["0"]; !ok {
		t.Fatal("part 0 missing")
	}
	if _, ok := call["1"]; !ok {
		t.Fatal("part 1 missing")
	}
}

func TestSingleFileListProducesOneSlot(t *testing.T) {
	h := newHarness(t)
	h.multipart.RegisterData("uploadFileList", object{"uploadFileList": userAliceJson})
	must(h.client.Mutations.UploadFileList(h.ctx, "user-1", []gl.GLUpload{makeFile(1, 2, 3)}))
	expectEqual(t, len(decodeMap(t, h.multipart.LastCall()["map"])), 1, "slots")
}
