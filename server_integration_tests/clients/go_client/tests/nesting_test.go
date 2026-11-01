package tests

import (
	"reflect"
	"testing"

	gl "graphlink.dev/serverintegration/generated"
)

func TestEnumListDepths(t *testing.T) {
	c := newClient(t)
	if got := must(c.Queries.Colors1(ctx(t))).Colors1; !reflect.DeepEqual(got, []gl.Color{gl.ColorRed, gl.ColorGreen, gl.ColorBlue}) {
		t.Fatalf("colors1: %v", got)
	}
	colors2 := must(c.Queries.Colors2(ctx(t))).Colors2
	if len(colors2) != 2 || len(colors2[0]) != 1 || len(colors2[1]) != 2 || *colors2[0][0] != gl.ColorRed || *colors2[1][1] != gl.ColorBlue {
		t.Fatalf("colors2: %v", colors2)
	}
	if got := must(c.Queries.Colors3(ctx(t))).Colors3; !reflect.DeepEqual(got, [][][]gl.Color{{{gl.ColorRed}}}) {
		t.Fatalf("colors3: %v", got)
	}
}

func TestTypeListDepths(t *testing.T) {
	c := newClient(t)
	if n := len(must(c.Queries.Boxes1(ctx(t))).Boxes1); n != 2 {
		t.Fatalf("boxes1: %d", n)
	}
	if n := len(must(c.Queries.Boxes2(ctx(t))).Boxes2); n != 2 {
		t.Fatalf("boxes2: %d", n)
	}
	if id := must(c.Queries.Boxes3(ctx(t))).Boxes3[0][0][0].Id; id != "b1" {
		t.Fatalf("boxes3: %q", id)
	}
}

func TestInterfaceListDepths(t *testing.T) {
	c := newClient(t)
	kinds := map[string]bool{}
	for _, s := range must(c.Queries.Shapes1(ctx(t))).Shapes1 {
		kinds[s.GetKind()] = true
	}
	if !kinds["circle"] || !kinds["square"] {
		t.Fatalf("kinds: %v", kinds)
	}
	if must(c.Queries.Shapes3(ctx(t))).Shapes3[0][0][0].GetKind() == "" {
		t.Fatal("empty kind")
	}
}

func TestUnionListDepths(t *testing.T) {
	c := newClient(t)
	m1 := must(c.Queries.Media1(ctx(t))).Media1
	if len(m1) != 2 {
		t.Fatalf("media1: %d", len(m1))
	}
	var photos []gl.Photo
	var videos []gl.Video
	for _, m := range m1 {
		switch v := m.(type) {
		case gl.Photo:
			photos = append(photos, v)
		case gl.Video:
			videos = append(videos, v)
		}
	}
	if len(photos) != 1 || photos[0].Width != 640 || len(videos) != 1 || videos[0].DurationSec != 30 {
		t.Fatalf("photos=%v videos=%v", photos, videos)
	}
	if m3 := must(c.Queries.Media3(ctx(t))).Media3; m3[0][0][0] == nil {
		t.Fatal("media3 empty")
	}
}
