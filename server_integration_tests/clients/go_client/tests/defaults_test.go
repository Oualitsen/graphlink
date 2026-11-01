package tests

import (
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

func TestInputFieldDefaultsAppliedWhenOmitted(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.ResolveConfig(ctx(t), gl.NewConfigInput())).ResolveConfig
	if res.PageSize != 25 || res.Ratio != 1.5 || res.Sort != "asc" || res.Verbose {
		t.Fatalf("unexpected config: %+v", res)
	}
	if res.Priority != gl.PriorityMedium || len(res.Tags) != 2 || res.Tags[0] != "default" || res.Tags[1] != "seed" {
		t.Fatalf("unexpected config: %+v", res)
	}
	if len(res.Empties) != 0 || res.Note != nil {
		t.Fatalf("unexpected config: %+v", res)
	}
}

func TestExplicitValuesOverrideDefaults(t *testing.T) {
	c := newClient(t)
	input := gl.NewConfigInput()
	input.PageSize = gl.Ptr(5)
	input.Sort = gl.Ptr("desc")
	input.Priority = gl.Ptr(gl.PriorityHigh)
	input.Note = gl.Ptr("x")
	res := must(c.Queries.ResolveConfig(ctx(t), input)).ResolveConfig
	if res.PageSize != 5 || res.Sort != "desc" || res.Priority != gl.PriorityHigh || *res.Note != "x" {
		t.Fatalf("unexpected config: %+v", res)
	}
}

func TestNestedObjectArgDefaultMergesWithFieldDefaults(t *testing.T) {
	c := newClient(t)
	r := must(c.Queries.ResolveRange(ctx(t))).ResolveRange
	if r.Min != 5 || r.Max != 100 {
		t.Fatalf("unexpected range: %+v", r)
	}
}

func TestArgumentLevelScalarDefaults(t *testing.T) {
	c := newClient(t)
	if got := must(c.Queries.Greet(ctx(t))).Greet; got != "Hi world!" {
		t.Fatalf("got %q", got)
	}
	got := must(c.Queries.Greet(ctx(t), gl.GreetOptions{Name: gl.Ptr("Bob"), Times: gl.Ptr(2)})).Greet
	if got != "Hi Bob!Hi Bob!" {
		t.Fatalf("got %q", got)
	}
}

func TestEnumArgumentPassedValueRoundTripsOmittedUsesDefaultHigh(t *testing.T) {
	c := newClient(t)
	low := must(c.Queries.EchoPriority(ctx(t), gl.EchoPriorityOptions{Level: gl.Ptr(gl.PriorityLow)})).EchoPriority
	if low != gl.PriorityLow {
		t.Fatalf("got %q", low)
	}
	if got := must(c.Queries.EchoPriority(ctx(t))).EchoPriority; got != gl.PriorityHigh {
		t.Fatalf("got %q", got)
	}
}
