package tests

import (
	"context"
	"fmt"
	"strings"
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

func scalarFixtureClient(t *testing.T, opaque string) *gl.GraphLinkClient {
	t.Helper()
	response := fmt.Sprintf(`{"data":{"scalarFixture":{"dt":"x","long":1,"dts":[],"opaque":%s}}}`, opaque)
	client, err := gl.NewGraphLinkClient(gl.GraphLinkClientOptions{
		Adapter:   func(context.Context, string) (string, error) { return response, nil },
		WsAdapter: gl.NewDefaultGraphLinkWebSocketAdapter(wsURL(defaultPort)),
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestCodecScalarOfTheWrongTypeFailsInsteadOfPanicking(t *testing.T) {
	for _, wire := range []string{`7`, `true`, `1.5`, `{"a":1}`, `["a"]`} {
		_, err := scalarFixtureClient(t, wire).Queries.ScalarFixture(ctx(t))
		if err == nil {
			t.Fatalf("%s was accepted for an Opaque", wire)
		}
		if !strings.Contains(err.Error(), "opaque") {
			t.Fatalf("the error does not name the field: %v", err)
		}
	}
}

func TestCodecScalarOfTheRightTypeStillRunsTheTemplate(t *testing.T) {
	bag := must(scalarFixtureClient(t, `"abc"`).Queries.ScalarFixture(ctx(t))).ScalarFixture
	expectEqual(t, *bag.Opaque, "opaque:abc", "opaque")
}

