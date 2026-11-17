package tests

import (
	"math"
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func echoWith(t *testing.T, change func(*gl.EverythingInput)) gl.EverythingEcho {
	t.Helper()
	input := gl.NewEverythingInput()
	change(&input)
	return must(newClient(t).Queries.EchoEverything(ctx(t), input)).EchoEverything
}

func TestIntAtBoth32BitLimits(t *testing.T) {
	r := echoWith(t, func(i *gl.EverythingInput) { i.I = gl.Ptr(2147483647); i.Neg = gl.Ptr(-2147483648) })
	expectEqual(t, *r.I, 2147483647, "i")
	expectEqual(t, *r.Neg, -2147483648, "neg")
}

func TestFloatAt1e308AndNegativeZero(t *testing.T) {
	r := echoWith(t, func(i *gl.EverythingInput) { i.F = gl.Ptr(1e308); i.Exp = gl.Ptr(math.Copysign(0, -1)) })
	expectEqual(t, *r.F, 1e308, "f")
	// encoding/json writes -0.0 as "-0", an integer literal, and the server reads it back as 0.
	expectEqual(t, math.Signbit(*r.Exp), false, "sign of -0.0")
}

func TestAStringWithANulCharacter(t *testing.T) {
	r := echoWith(t, func(i *gl.EverythingInput) { i.S = gl.Ptr("a\x00b") })
	expectEqual(t, *r.S, "a\x00b", "s")
}

// A Go string cannot hold a lone surrogate: the UTF-8 bytes of one are invalid and encoding/json sends U+FFFD.
func TestInvalidUtf8BecomesTheReplacementCharacter(t *testing.T) {
	r := echoWith(t, func(i *gl.EverythingInput) { i.S = gl.Ptr("x\xed\xa0\x80y") })
	expectEqual(t, *r.S, "x���y", "s")
}
