package tests

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"testing"

	"graphlink.dev/resttests/generated"
)

func TestScalarsAndPaths(t *testing.T) {
	ctx, client := setup(t)
	st := generated.StatusArchived
	e := must(client.Queries.EScalars(ctx, "x1", generated.EScalarsOptions{
		S: str("hello"), I: generated.Ptr(3), F: generated.Ptr(2.5), B: generated.Ptr(true), St: &st, Renamed: str("r"),
	}))
	eq(t, e.Method, "GET")
	eq(t, e.Path, "/echo/scalars/x1")
	eq(t, pairs(e.Query), []string{"s=hello", "i=3", "f=2.5", "b=true", "st=ARCHIVED", "dflt=5", "x-ren=r"})
	eq(t, e.BodySize, 0)
	isTrue(t, e.ContentType == nil, "GET must not send a Content-Type")
	accept, _ := header(e, "accept")
	eq(t, accept, "application/json")

	eq(t, pairs(must(client.Queries.EScalars(ctx, "x1")).Query), []string{"dflt=5"})
	eq(t, pairs(must(client.Queries.EScalars(ctx, "x1", generated.EScalarsOptions{Dflt: generated.Ptr(9)})).Query), []string{"dflt=9"})

	zero := must(client.Queries.EScalars(ctx, "x1", generated.EScalarsOptions{B: generated.Ptr(false), I: generated.Ptr(0), S: str("")}))
	eq(t, pairs(zero.Query), []string{"s=", "i=0", "b=false", "dflt=5"})
}

func TestReservedAndNonAsciiCharacters(t *testing.T) {
	ctx, client := setup(t)
	segment := "a b/c?d#é+%"
	value := "a&b=c d+e/é\"%25"
	e := must(client.Queries.ESpecial(ctx, segment, value, generated.ESpecialOptions{Other: str("ü")}))
	eq(t, e.Path, "/echo/special/"+strings.ReplaceAll(url.QueryEscape(segment), "+", "%20")+"/tail")
	v, _ := queryValue(e, "q")
	eq(t, v, value)
	o, _ := queryValue(e, "other")
	eq(t, o, "ü")
	empty := must(client.Queries.ESpecial(ctx, "seg", ""))
	q, found := queryValue(empty, "q")
	isTrue(t, found, "an empty value must not be dropped")
	eq(t, q, "")
}

func TestDeleteCarriesArgumentsInTheQuery(t *testing.T) {
	ctx, client := setup(t)
	e := must(client.Queries.EDeleteQuery(ctx, "d1", generated.EDeleteQueryOptions{Force: generated.Ptr(true)}))
	eq(t, []any{e.Method, e.Path, e.BodySize}, []any{"DELETE", "/echo/delete/d1", 0})
	eq(t, pairs(e.Query), []string{"force=true"})
}

func TestLists(t *testing.T) {
	ctx, client := setup(t)
	e := must(client.Queries.ELists(ctx, generated.EListsOptions{Tags: []string{"a", "b c"}, Ids: []int{1, 2, 3}, Empty: []string{}}))
	eq(t, pairs(e.Query), append(list("tags", "a", "b c"), list("ids", "1", "2", "3")...))
	_, found := queryValue(e, "empty")
	isTrue(t, !found, "an empty list sends nothing")

	m := must(client.Queries.ELists(ctx, generated.EListsOptions{Matrix: [][]int{{1, 2}, {3}}}))
	eq(t, pairs(m.Query), []string{key("matrix", "0", "0") + "=1", key("matrix", "0", "1") + "=2", key("matrix", "1", "0") + "=3"})

	rows := must(client.Queries.ELists(ctx, generated.EListsOptions{Rows: []generated.Row{{Name: "r0", Ids: []int{1, 2}}, {Name: "r1"}}}))
	expected := append([]string{key("rows", "0", "name") + "=r0"}, list(key("rows", "0", "ids"), "1", "2")...)
	expected = append(expected, key("rows", "1", "name")+"=r1")
	eq(t, pairs(rows.Query), expected)

	tags := must(client.Queries.ELists(ctx, generated.EListsOptions{Tags: []string{"a&b", "c=d", "e f", "é"}}))
	if comma {
		v, _ := queryValue(tags, "tags")
		eq(t, v, "a&b,c=d,e f,é")
	} else {
		var values []string
		for _, p := range tags.Query {
			if p.Name == "tags" {
				values = append(values, p.Value)
			}
		}
		eq(t, strings.Join(values, "|"), "a&b|c=d|e f|é")
	}
}

func TestObjects(t *testing.T) {
	ctx, client := setup(t)
	active := generated.StatusActive
	spread := must(client.Queries.EObjects(ctx, generated.EObjectsOptions{Filter: &generated.Filter{Tag: str("x"), MinPrice: generated.Ptr(3.0), Status: &active}}))
	eq(t, pairs(spread.Query), []string{"tag=x", "minPrice=3", "status=ACTIVE"})
	only := must(client.Queries.EObjects(ctx, generated.EObjectsOptions{Filter: &generated.Filter{Tag: str("x")}}))
	eq(t, pairs(only.Query), []string{"tag=x"})

	meta := &generated.Meta{Name: "m", Tags: []string{"t1", "t2"}, Address: &generated.Address{
		City: str("Oran"), Street: str("Rue 1"), Geo: &generated.Geo{Lat: generated.Ptr(35.7), Lng: generated.Ptr(-0.6)},
	}}
	flat := must(client.Queries.EObjects(ctx, generated.EObjectsOptions{Meta: meta}))
	expected := append([]string{key("meta", "name") + "=m"}, list(key("meta", "tags"), "t1", "t2")...)
	expected = append(expected,
		key("meta", "address", "city")+"=Oran", key("meta", "address", "street")+"=Rue 1",
		key("meta", "address", "geo", "lat")+"=35.7", key("meta", "address", "geo", "lng")+"=-0.6")
	eq(t, pairs(flat.Query), expected)

	asJSON := must(client.Queries.EObjects(ctx, generated.EObjectsOptions{AsJson: &generated.Meta{Name: "m", Tags: []string{"a"}, Address: &generated.Address{City: str("c")}}}))
	eq(t, len(asJSON.Query), 1)
	eq(t, asJSON.Query[0].Name, "j")
	var decoded map[string]any
	mustOK(json.Unmarshal([]byte(asJSON.Query[0].Value), &decoded))
	eq(t, decoded["name"], "m")
	eq(t, decoded["address"].(map[string]any)["city"], "c")

	all := must(client.Queries.EObjects(ctx, generated.EObjectsOptions{Filter: &generated.Filter{Tag: str("x")}, Meta: &generated.Meta{Name: "m"}, AsJson: &generated.Meta{Name: "j"}}))
	names := map[string]bool{}
	for _, p := range all.Query {
		names[p.Name] = true
	}
	eq(t, names, map[string]bool{"tag": true, key("meta", "name"): true, "j": true})
}

func TestHeaders(t *testing.T) {
	ctx, client := setup(t)
	e := must(client.Queries.EHeaders(ctx, "t-1", generated.EHeadersOptions{Trace: &generated.Trace{TraceId: str("tr"), SpanId: str("sp")}}))
	for name, expected := range map[string]string{"X-Tenant": "t-1", "X-Trace-Id": "tr", "X-Span-Id": "sp"} {
		v, _ := header(e, name)
		eq(t, v, expected)
	}
	partial := must(client.Queries.EHeaders(ctx, "t", generated.EHeadersOptions{Trace: &generated.Trace{TraceId: str("tr")}}))
	for _, name := range []string{"X-Span-Id", "X-Opt", "X-Roles"} {
		_, found := header(partial, name)
		isTrue(t, !found, name+" must not be sent")
	}
	roles := must(client.Queries.EHeaders(ctx, "t", generated.EHeadersOptions{Roles: []string{"admin", "ops"}}))
	v, _ := header(roles, "X-Roles")
	eq(t, v, "admin,ops")

	plain := must(client.Queries.EAccept(ctx))
	accept, _ := header(plain, "accept")
	eq(t, accept, "application/json")
	isTrue(t, plain.ContentType == nil, "GET must not send a Content-Type")
	override := must(client.Queries.EAcceptOverride(ctx))
	accept, _ = header(override, "accept")
	eq(t, accept, "application/vnd.test+json")
}

func TestAdapterHeaders(t *testing.T) {
	ctx, _ := setup(t)
	calls := 0
	provider := newClient(t, clientOptions{headers: func(context.Context) (map[string]string, error) {
		calls++
		return map[string]string{"X-Provider": "call-" + string(rune('0'+calls))}, nil
	}})
	first, _ := header(must(provider.Queries.EAccept(ctx)), "X-Provider")
	second, _ := header(must(provider.Queries.EAccept(ctx)), "X-Provider")
	eq(t, []string{first, second}, []string{"call-1", "call-2"})

	override := newClient(t, clientOptions{headers: func(context.Context) (map[string]string, error) {
		return map[string]string{"X-Tenant": "from-provider", "X-Other": "kept"}, nil
	}})
	e := must(override.Queries.EHeaders(ctx, "from-arg"))
	tenant, _ := header(e, "X-Tenant")
	other, _ := header(e, "X-Other")
	eq(t, []string{tenant, other}, []string{"from-arg", "kept"})

	_, err := newClient(t).Queries.AuthCheck(ctx)
	failure := restError(t, err)
	eq(t, failure.Status, 401)
	eq(t, failure.Headers["www-authenticate"], "Bearer")
	authed := newClient(t, clientOptions{headers: func(context.Context) (map[string]string, error) {
		return map[string]string{"Authorization": "Bearer secret"}, nil
	}})
	who := must(authed.Queries.AuthCheck(ctx, generated.AuthCheckOptions{Tenant: str("acme")}))
	eq(t, who.User, "ann")
	eq(t, ptrString(who.Tenant), "acme")
}
