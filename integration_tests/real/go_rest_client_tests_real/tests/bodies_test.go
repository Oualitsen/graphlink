package tests

import (
	"io"
	"strings"
	"testing"
	"unicode/utf8"

	"graphlink.dev/resttests/generated"
)

func asMap(t *testing.T, e generated.Echo) map[string]any {
	t.Helper()
	m, ok := bodyJSON(t, e).(map[string]any)
	isTrue(t, ok, "body is not a JSON object")
	return m
}

func TestJSONBody(t *testing.T) {
	ctx, client := setup(t)
	archived := generated.StatusArchived
	e := must(client.Mutations.EJson(ctx, generated.ProductIn{Name: "Pen", Price: generated.Ptr(2.5), Status: &archived, Tags: []string{"a", "b"}}))
	eq(t, []string{e.Method, e.Path}, []string{"POST", "/echo/json"})
	isTrue(t, strings.HasPrefix(ptrString(e.ContentType), "application/json"), "content type")
	body := asMap(t, e)
	eq(t, body["name"], "Pen")
	eq(t, body["price"], 2.5)
	eq(t, body["status"], "ARCHIVED")
	eq(t, body["tags"], []any{"a", "b"})
	_, wrapped := body["body"]
	isTrue(t, !wrapped, "the argument must be unwrapped")

	l := must(client.Mutations.EJsonList(ctx, []generated.ProductIn{{Name: "a"}, {Name: "b"}}))
	items := bodyJSON(t, l).([]any)
	eq(t, []any{items[0].(map[string]any)["name"], items[1].(map[string]any)["name"]}, []any{"a", "b"})
	empty := must(client.Mutations.EJsonList(ctx, []generated.ProductIn{}))
	eq(t, bodyJSON(t, empty), []any{})
}

func TestOptionalJSONBodyAndContentType(t *testing.T) {
	ctx, client := setup(t)
	none := must(client.Mutations.EJsonOptional(ctx))
	eq(t, none.BodySize, 0)
	isTrue(t, none.ContentType == nil, "no body, no Content-Type")
	present := must(client.Mutations.EJsonOptional(ctx, generated.EJsonOptionalOptions{Body: &generated.ProductIn{Name: "x"}}))
	eq(t, asMap(t, present)["name"], "x")
	typed := must(client.Mutations.EJsonType(ctx, generated.ProductIn{Name: "x"}))
	isTrue(t, strings.HasPrefix(ptrString(typed.ContentType), "application/vnd.test+json"), "custom content type")
}

func TestJSONBodyContent(t *testing.T) {
	ctx, client := setup(t)
	name := "é漢😀 \"quoted\" \\ back\nline"
	e := must(client.Mutations.EJson(ctx, generated.ProductIn{Name: name}))
	eq(t, asMap(t, e)["name"], name)
	eq(t, e.BodySize, len(ptrString(e.BodyText)))
	isTrue(t, utf8.ValidString(ptrString(e.BodyText)), "valid UTF-8")

	tags := make([]string, 20000)
	for i := range tags {
		tags[i] = "tag-" + strings.Repeat("x", 1)
	}
	big := must(client.Mutations.EJson(ctx, generated.ProductIn{Name: "big", Tags: tags}))
	eq(t, len(asMap(t, big)["tags"].([]any)), 20000)
}

func TestMethodsAndRoles(t *testing.T) {
	ctx, client := setup(t)
	put := must(client.Mutations.EPut(ctx, "a b", generated.ProductIn{Name: "x"}))
	eq(t, []string{put.Method, put.Path}, []string{"PUT", "/echo/put/a%20b"})
	patch := must(client.Mutations.EPatch(ctx, "p", generated.ProductIn{Name: "x"}))
	eq(t, []string{patch.Method, patch.Path}, []string{"PATCH", "/echo/patch/p"})
	hb := must(client.Mutations.EHeaderBody(ctx, "i1", "acme", generated.ProductIn{Name: "x"}))
	eq(t, hb.Path, "/echo/hb/i1")
	tenant, _ := header(hb, "x-tenant")
	eq(t, tenant, "acme")
	eq(t, asMap(t, hb)["name"], "x")
}

func TestFormBody(t *testing.T) {
	ctx, client := setup(t)
	e := must(client.Mutations.EForm(ctx, "Pen", generated.EFormOptions{N: generated.Ptr(3)}))
	eq(t, e.Method, "POST")
	isTrue(t, strings.HasPrefix(ptrString(e.ContentType), "application/x-www-form-urlencoded"), "content type")
	eq(t, pairs(e.Form), []string{"name=Pen", "n=3"})

	value := "a&b=c d+e%f/é😀\n"
	eq(t, formValue(must(client.Mutations.EForm(ctx, value)), "name"), value)

	lists := must(client.Mutations.EForm(ctx, "n", generated.EFormOptions{Tags: []string{"x", "y z"}}))
	eq(t, pairs(lists.Form), append([]string{"name=n"}, list("tags", "x", "y z")...))

	nested := must(client.Mutations.EForm(ctx, "n", generated.EFormOptions{Meta: &generated.Meta{Name: "m", Address: &generated.Address{City: str("Oran")}}}))
	eq(t, pairs(nested.Form), []string{"name=n", key("meta", "name") + "=m", key("meta", "address", "city") + "=Oran"})

	spread := must(client.Mutations.EForm(ctx, "n", generated.EFormOptions{Filter: &generated.Filter{Tag: str("t"), MinPrice: generated.Ptr(1.0)}}))
	eq(t, pairs(spread.Form), []string{"name=n", "tag=t", "minPrice=1"})

	asJSON := must(client.Mutations.EForm(ctx, "n", generated.EFormOptions{AsJson: &generated.Meta{Name: "m"}}))
	isTrue(t, strings.Contains(formValue(asJSON, "j"), `"name":"m"`), "json entry")

	eq(t, pairs(must(client.Mutations.EForm(ctx, "n")).Form), []string{"name=n"})
	empty := must(client.Mutations.EFormEmpty(ctx))
	eq(t, empty.BodySize, 0)
	isTrue(t, empty.ContentType == nil, "no body, no Content-Type")
	eq(t, pairs(must(client.Mutations.EFormEmpty(ctx, generated.EFormEmptyOptions{B: generated.Ptr(0)})).Form), []string{"b=0"})
}

func TestMultipartBody(t *testing.T) {
	ctx, client := setup(t)
	text := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{Title: str("Hello é")}))
	isTrue(t, strings.HasPrefix(ptrString(text.ContentType), "multipart/form-data; boundary="), "boundary")
	title := part(t, text, "title")
	isTrue(t, title.Filename == nil, "text part has no filename")
	eq(t, ptrString(title.Text), "Hello é")

	data := pattern(70000)
	one := upload(data, "photo.png", "image/png")
	file := part(t, must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{One: &one})), "one")
	eq(t, ptrString(file.Filename), "photo.png")
	isTrue(t, strings.HasPrefix(ptrString(file.ContentType), "image/png"), "part mime type")
	eq(t, []any{file.Size, file.Sha256}, []any{len(data), sha(data)})

	files := [][]byte{pattern(10), pattern(2000), {}}
	var many []generated.GLUpload
	for i, f := range files {
		many = append(many, upload(f, "f"+string(rune('0'+i))+".bin", ""))
	}
	parts := partsNamed(must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{Many: many})), "many")
	eq(t, len(parts), 3)
	for i, f := range files {
		eq(t, []any{parts[i].Size, parts[i].Sha256}, []any{len(f), sha(f)})
		eq(t, ptrString(parts[i].Filename), "f"+string(rune('0'+i))+".bin")
	}

	unicode := upload(pattern(3), "é漢.png", "")
	name := ptrString(part(t, must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{One: &unicode})), "one").Filename)
	isTrue(t, name == "é漢.png" || name == "%C3%A9%E6%BC%A2.png", "filename survives: "+name)
}

func TestMultipartObjectsAndMixes(t *testing.T) {
	ctx, client := setup(t)
	e := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{Meta: &generated.Meta{Name: "m", Tags: []string{"a", "b"}, Address: &generated.Address{City: str("Oran")}}}))
	eq(t, ptrString(part(t, e, key("meta", "name")).Text), "m")
	var tags []string
	for _, p := range partsNamed(e, key("meta", "tags")) {
		tags = append(tags, ptrString(p.Text))
	}
	if comma {
		eq(t, tags, []string{"a,b"})
	} else {
		eq(t, tags, []string{"a", "b"})
	}
	eq(t, ptrString(part(t, e, key("meta", "address", "city")).Text), "Oran")

	j := part(t, must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{AsJson: &generated.Meta{Name: "m"}})), "j")
	isTrue(t, strings.HasPrefix(ptrString(j.ContentType), "application/json"), "json part type")
	isTrue(t, strings.Contains(ptrString(j.Text), `"name":"m"`), "json part body")

	data := pattern(1000)
	one := upload(data, "a.bin", "")
	together := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{
		Title: str("t"), AsJson: &generated.Meta{Name: "m"}, One: &one,
		Many: []generated.GLUpload{upload(data, "b.bin", ""), upload(data, "c.bin", "")},
	}))
	var names []string
	for _, p := range together.Parts {
		names = append(names, p.Name)
	}
	eq(t, names, []string{"title", "j", "one", "many", "many"})

	nothing := must(client.Mutations.EMultipart(ctx))
	eq(t, nothing.BodySize, 0)
	isTrue(t, nothing.ContentType == nil, "no parts, no body")
}

func TestMultipartProgress(t *testing.T) {
	ctx, client := setup(t)
	data := pattern(1_500_000)
	one := upload(data, "big.bin", "")
	var reports [][2]int64
	e := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{One: &one, OnProgress: func(sent, total int64) {
		reports = append(reports, [2]int64{sent, total})
	}}))
	eq(t, part(t, e, "one").Sha256, sha(data))
	isTrue(t, len(reports) > 0, "progress reported")
	for i := 1; i < len(reports); i++ {
		isTrue(t, reports[i][0] >= reports[i-1][0], "progress never decreases")
	}
	last := reports[len(reports)-1]
	eq(t, last[0], last[1])
	isTrue(t, last[1] > int64(len(data)), "total includes the multipart framing")
}

func TestRawBody(t *testing.T) {
	ctx, client := setup(t)
	data := pattern(120000)
	e := must(client.Mutations.ERaw(ctx, upload(data, "", "image/png")))
	eq(t, e.Method, "PUT")
	isTrue(t, strings.HasPrefix(ptrString(e.ContentType), "image/png"), "upload mime type")
	eq(t, []any{e.BodySize, e.BodySha256}, []any{len(data), sha(data)})
	isTrue(t, e.ContentLength != nil && *e.ContentLength == len(data), "known length")
	isTrue(t, !e.Chunked, "not chunked")

	def := must(client.Mutations.ERaw(ctx, upload(pattern(5), "", "")))
	isTrue(t, strings.HasPrefix(ptrString(def.ContentType), "application/octet-stream"), "default mime type")
	typed := must(client.Mutations.ERawType(ctx, upload(pattern(5), "", "image/png")))
	isTrue(t, strings.HasPrefix(ptrString(typed.ContentType), "application/x-custom"), "operation content type")

	eq(t, must(client.Mutations.ERaw(ctx, upload(nil, "", ""))).BodySize, 0)
	nothing := must(client.Mutations.ERawOptional(ctx))
	eq(t, nothing.BodySize, 0)
	isTrue(t, nothing.ContentType == nil, "no file, no body")

	named := must(client.Mutations.ERaw(ctx, upload(pattern(5), "secret-name.bin", "")))
	for _, h := range named.Headers {
		isTrue(t, !strings.Contains(h.Value, "secret-name"), "the filename must not be sent")
	}
	_, found := header(named, "content-disposition")
	isTrue(t, !found, "no content-disposition")
}

func TestRawBodyStreamedAndProgress(t *testing.T) {
	ctx, client := setup(t)
	data := pattern(6 * 1024 * 1024)
	var last [2]int64
	var previous int64
	e := must(client.Mutations.ERaw(ctx, upload(data, "", ""), generated.ERawOptions{OnProgress: func(sent, total int64) {
		isTrue(t, sent >= previous, "progress never decreases")
		previous, last = sent, [2]int64{sent, total}
	}}))
	eq(t, e.BodySha256, sha(data))
	eq(t, last, [2]int64{int64(len(data)), int64(len(data))})

	unknown := generated.NewGLUpload(io.NopCloser(strings.NewReader(string(pattern(250000)))), "")
	chunked := must(client.Mutations.ERaw(ctx, unknown))
	isTrue(t, chunked.Chunked, "unknown length is chunked")
	isTrue(t, chunked.ContentLength == nil, "no content length")
	eq(t, chunked.BodySha256, sha(pattern(250000)))
}

func TestMultipartStreamsWithAndWithoutLength(t *testing.T) {
	ctx, client := setup(t)
	data := pattern(300000)
	known := upload(data, "k.bin", "")
	withLength := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{One: &known}))
	isTrue(t, withLength.ContentLength != nil && !withLength.Chunked, "known lengths send Content-Length")
	eq(t, part(t, withLength, "one").Sha256, sha(data))

	unknown := generated.NewGLUpload(io.NopCloser(strings.NewReader(string(data))), "u.bin")
	chunked := must(client.Mutations.EMultipart(ctx, generated.EMultipartOptions{One: &unknown}))
	isTrue(t, chunked.Chunked && chunked.ContentLength == nil, "unknown length is chunked")
	eq(t, part(t, chunked, "one").Sha256, sha(data))
}
