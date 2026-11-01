package tests

import (
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

func TestReservedWordFieldsRoundTrip(t *testing.T) {
	c := newClient(t)
	r := must(c.Queries.Reserved(ctx(t))).Reserved
	if r.Class != "cls" || r.Return != 42 || !r.New || r.Default != "def" {
		t.Fatalf("unexpected: %+v", r)
	}
	if r.Is != "yes" || r.In != "inside" || r.With != "w" || r.Int != 7 || r.Synchronized || r.Native != "n" {
		t.Fatalf("unexpected: %+v", r)
	}
	if r.Kind != gl.KeywordClass || r.Nested.Value != "v" || r.Secret.Token != "tok" {
		t.Fatalf("unexpected: %+v", r)
	}
}

func TestReservedOperationNamePlusReservedArgumentNames(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.Switch(ctx(t), "x", gl.SwitchOptions{Return: gl.Ptr(5)})).Switch
	if res.Class != "x" || res.Return != 5 {
		t.Fatalf("unexpected: %+v", res)
	}
}

func TestLeadingUnderscoreOperation(t *testing.T) {
	c := newClient(t)
	if got := must(c.Queries.Status(ctx(t))).Status; got != "ok" {
		t.Fatalf("got %q", got)
	}
}

func TestCollidingFieldNamesStayDistinct(t *testing.T) {
	c := newClient(t)
	col := must(c.Queries.Collide(ctx(t))).Collide
	if !((col.Class == "A" && col.Class2 == "B") || (col.Class == "B" && col.Class2 == "A")) {
		t.Fatalf("unexpected: %+v", col)
	}
}

func TestReservedWordInputFieldsMutation(t *testing.T) {
	c := newClient(t)
	res := must(c.Mutations.EchoReserved(ctx(t), gl.ReservedInput{Class: "X", Return: gl.Ptr(5), Default: gl.Ptr("D"), Is: gl.Ptr(true), Synchronized: gl.Ptr(3)}))
	if res.EchoReserved.Class != "X" || res.EchoReserved.Return != 5 || res.EchoReserved.Default != "D" {
		t.Fatalf("unexpected: %+v", res.EchoReserved)
	}
}
