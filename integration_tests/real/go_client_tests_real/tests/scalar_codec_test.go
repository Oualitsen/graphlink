package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestCodecScalarIsDecodedInAResponse(t *testing.T) {
	bag := must(newClient(t).Queries.ScalarFixture(ctx(t))).ScalarFixture
	expectEqual(t, *bag.Opaque, "opaque:o-1", "opaque")
}

func TestCodecScalarIsEncodedInAnInputFieldAndDecodedAgain(t *testing.T) {
	input := gl.ScalarsInput{Dt: "x", Long: 1, Dts: []string{}, Opaque: gl.Ptr("opaque:xyz")}
	bag := must(newClient(t).Queries.EchoScalars(ctx(t), input)).EchoScalars
	expectEqual(t, *bag.Opaque, "opaque:xyz", "opaque")
}

func TestCodecScalarIsEncodedInAnOperationArgumentAndDecodedAgain(t *testing.T) {
	bag := must(newClient(t).Queries.EchoScalarArgs(ctx(t), "x", []string{}, gl.EchoScalarArgsOptions{Opaque: gl.Ptr("opaque:abc")})).EchoScalarArgs
	expectEqual(t, *bag.Opaque, "opaque:abc", "opaque")
}

func TestCodecScalarKeepsNullAsNull(t *testing.T) {
	fromArgs := must(newClient(t).Queries.EchoScalarArgs(ctx(t), "x", []string{})).EchoScalarArgs
	if fromArgs.Opaque != nil {
		t.Fatal("opaque must stay nil")
	}
	fromInput := must(newClient(t).Queries.EchoScalars(ctx(t), gl.ScalarsInput{Dt: "x", Long: 1, Dts: []string{}})).EchoScalars
	if fromInput.Opaque != nil {
		t.Fatal("opaque must stay nil")
	}
}

func TestAliasScalarsKeepLongPrecisionAndJsonShape(t *testing.T) {
	bag := must(newClient(t).Queries.ScalarFixture(ctx(t))).ScalarFixture
	expectEqual(t, bag.Long, int64(9007199254740993), "long")
	expectEqual(t, *bag.Longs[2], int64(9223372036854775807), "longs[2]")
	expectEqual(t, bag.Dt, "2026-01-02T03:04:05Z", "dt")
	expectDeep(t, bag.Json, map[string]any{"name": "x", "n": float64(1), "list": []any{float64(1), "two", false}}, "json")
}

func TestLongDefaultReachesTheServer(t *testing.T) {
	bag := must(newClient(t).Queries.EchoScalarArgs(ctx(t), "x", []string{})).EchoScalarArgs
	expectEqual(t, bag.Long, int64(9007199254740993), "long")
}
