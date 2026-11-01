package tests

import (
	"encoding/json"
	"strings"
	"testing"

	gl "graphlink.dev/mocktests/generated"
)

func TestFetchUserAndPost(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("fetchUserAndPost", object{"user": userAliceJson, "post": postJson})
	res := must(h.client.Queries.FetchUserAndPost(h.ctx, "user-1", "post-1"))
	expectEqual(t, res.User.Name, "Alice Smith", "user name")
	expectEqual(t, res.User.Id, "user-1", "user id")
	expectEqual(t, res.Post.Title, "Hello World", "post title")
	expectEqual(t, res.Post.Author.Id, "user-1", "post author id")
}

func TestFetchUserSummaryProjectedType(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("fetchUserSummary", object{"getUser": object{"id": "user-1", "name": "Alice Smith", "status": "ACTIVE"}})
	res := must(h.client.Queries.FetchUserSummary(h.ctx, "user-1"))
	expectEqual(t, res.GetUser.Id, "user-1", "id")
	expectEqual(t, res.GetUser.Name, "Alice Smith", "name")
	expectEqual(t, res.GetUser.Status, gl.UserStatusActive, "status")
}

func TestFetchCachedPairIndependentCaching(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("fetchCachedPair", object{"user": userAliceJson, "post": postJson})
	must(h.client.Queries.FetchCachedPair(h.ctx, "user-1", "post-1"))
	res := must(h.client.Queries.FetchCachedPair(h.ctx, "user-1", "post-1"))
	expectEqual(t, h.adapter.CallCount(), 1, "second call hits the cache")
	expectEqual(t, res.User.Name, "Alice Smith", "user name on cache hit")
	expectEqual(t, res.Post.Title, "Hello World", "post title on cache hit")
	must(h.client.Queries.FetchCachedPair(h.ctx, "user-1", "post-2"))
	expectEqual(t, h.adapter.CallCount(), 2, "different postId is a miss")
}

var searchResults = list{
	object{"__typename": "UserResult", "id": "ur-1", "name": "Alice", "email": "alice@test.com"},
	object{"__typename": "PostResult", "id": "pr-1", "title": "Hello World"},
}

func TestSearchUnionDispatch(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("search", object{"search": searchResults})
	res := must(h.client.Queries.Search(h.ctx, "test"))
	expectEqual(t, len(res.Search), 2, "length")
	user, ok := res.Search[0].(gl.UserResult)
	if !ok || user.Id != "ur-1" || user.Name != "Alice" || user.Email != "alice@test.com" {
		t.Fatalf("unexpected first element: %#v", res.Search[0])
	}
	post, ok := res.Search[1].(gl.PostResult)
	if !ok || post.Id != "pr-1" || post.Title != "Hello World" {
		t.Fatalf("unexpected second element: %#v", res.Search[1])
	}
}

func TestSearchUnknownTypenameFails(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("search", object{"search": list{object{"__typename": "UnknownType", "id": "x-1"}}})
	if _, err := h.client.Queries.Search(h.ctx, "test"); err == nil {
		t.Fatal("expected an error for an unknown __typename")
	}
}

func TestRunSearchCustomQueryDispatch(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("runSearch", object{"search": searchResults})
	res := must(h.client.Queries.RunSearch(h.ctx, "test"))
	expectEqual(t, len(res.Search), 2, "length")
	if _, ok := res.Search[0].(gl.UserResult); !ok {
		t.Fatalf("first element: %#v", res.Search[0])
	}
	if _, ok := res.Search[1].(gl.PostResult); !ok {
		t.Fatalf("second element: %#v", res.Search[1])
	}
}

func sentQuery(h *harness) string {
	var payload struct {
		Query string `json:"query"`
	}
	if err := json.Unmarshal([]byte(h.adapter.LastCall().RawPayload), &payload); err != nil {
		panic(err)
	}
	return payload.Query
}

func TestLiteralArguments(t *testing.T) {
	h := newHarness(t)

	h.adapter.RegisterData("findFirstUser", object{"findUser": userAliceJson})
	res := must(h.client.Queries.FindFirstUser(h.ctx))
	expectEqual(t, res.FindUser.Name, "Alice Smith", "name")
	expectEqual(t, len(h.adapter.LastCall().Variables), 0, "variables")
	if !strings.Contains(sentQuery(h), `findUser(id: "user-1")`) {
		t.Fatalf("string literal not inlined: %s", sentQuery(h))
	}

	h.adapter.RegisterData("listActiveUsers", object{"listUsersByStatus": list{userAliceJson}})
	active := must(h.client.Queries.ListActiveUsers(h.ctx))
	expectEqual(t, len(active.ListUsersByStatus), 1, "active users")
	if !strings.Contains(sentQuery(h), `listUsersByStatus(status: ACTIVE)`) {
		t.Fatalf("enum literal not inlined: %s", sentQuery(h))
	}

	h.adapter.RegisterData("searchAlice", object{"searchUsers": list{userAliceJson}})
	must(h.client.Queries.SearchAlice(h.ctx))
	expectEqual(t, len(h.adapter.LastCall().Variables), 0, "variables")
	if !strings.Contains(sentQuery(h), `searchUsers(name: "Alice",limit: 5)`) {
		t.Fatalf("several literals not inlined: %s", sentQuery(h))
	}

	h.adapter.RegisterData("searchWithFixedLimit", object{"searchUsers": list{userBobJson}})
	must(h.client.Queries.SearchWithFixedLimit(h.ctx, "Bob"))
	if v := h.adapter.LastCall().Variables; len(v) != 1 || v["name"] != "Bob" {
		t.Fatalf("variables: %v", v)
	}
	if !strings.Contains(sentQuery(h), `searchUsers(name: $name,limit: 10)`) {
		t.Fatalf("mixed literal and variable: %s", sentQuery(h))
	}

	h.adapter.RegisterData("searchPrice", object{"searchUsers": list{}})
	must(h.client.Queries.SearchPrice(h.ctx))
	expectEqual(t, len(h.adapter.LastCall().Variables), 0, "variables")
	if !strings.Contains(sentQuery(h), `name: "cost $5 or $6"`) {
		t.Fatalf("dollar signs altered: %s", sentQuery(h))
	}
}

func TestCycleUserPostsUser(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userWithPostsJson})
	user := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser
	expectEqual(t, len(user.Posts), 1, "posts")
	post := user.Posts[0]
	expectEqual(t, post.Id, "post-10", "post id")
	expectEqual(t, post.Title, "Cyclic Post", "title")
	expectEqual(t, post.ViewCount, 7, "viewCount")
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Name, "Alice Smith", "author name")
	expectEqual(t, post.Author.Address.City, "Springfield", "author city")

	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	if posts := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser.Posts; posts != nil {
		t.Fatalf("expected nil posts, got %v", posts)
	}
}

func TestCyclePostAuthorPost(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getPost", object{"getPost": postWithAuthorCycleJson})
	post := must(h.client.Queries.GetPost(h.ctx, "post-10")).GetPost
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Email, "alice@test.com", "author email")
	if len(post.Author.Tags) != 1 || post.Author.Tags[0] != "admin" {
		t.Fatalf("tags: %v", post.Author.Tags)
	}
}

func TestListUsersWithCyclicPosts(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listUsers", object{"listUsers": list{userWithPostsJson}})
	users := must(h.client.Queries.ListUsers(h.ctx)).ListUsers
	expectEqual(t, len(users), 1, "users")
	expectEqual(t, users[0].Posts[0].Title, "Cyclic Post", "post title")
}

func TestEnumDeserialization(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	alice := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser
	expectEqual(t, alice.Status, gl.UserStatusActive, "status")
	if alice.Priority == nil || *alice.Priority != gl.PriorityHigh {
		t.Fatalf("priority: %v", alice.Priority)
	}
	h.adapter.RegisterData("getUser", object{"getUser": userBobJson})
	bob := must(h.client.Queries.GetUser(h.ctx, "user-2")).GetUser
	expectEqual(t, bob.Status, gl.UserStatusInactive, "bob status")
	if bob.Priority != nil {
		t.Fatalf("expected nil priority, got %v", *bob.Priority)
	}
}

func TestUnknownEnumValueFallsBack(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": merge(userAliceJson, object{"status": "BANNED"})})
	res := must(h.client.Queries.GetUser(h.ctx, "user-1"))
	expectEqual(t, res.GetUser.Status, gl.UserStatusUnknownValue__, "status")
}

func TestUnknownFallbackIsNeverSentBack(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listUsersByStatus", object{"listUsersByStatus": list{}})
	if _, err := h.client.Queries.ListUsersByStatus(h.ctx, gl.UserStatusUnknownValue__); err == nil {
		t.Fatal("expected the fallback value to be rejected")
	}
}

func TestEnumSerializationInQueryVariables(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listUsersByStatus", object{"listUsersByStatus": list{}})
	for status, wire := range map[gl.UserStatus]string{
		gl.UserStatusActive: "ACTIVE", gl.UserStatusInactive: "INACTIVE", gl.UserStatusSuspended: "SUSPENDED",
	} {
		must(h.client.Queries.ListUsersByStatus(h.ctx, status))
		expectEqual(t, h.adapter.LastCall().Variables["status"].(string), wire, "status variable")
	}
}

func TestEnumInListResponse(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listUsers", object{"listUsers": list{userAliceJson, userBobJson}})
	users := must(h.client.Queries.ListUsers(h.ctx)).ListUsers
	expectEqual(t, users[0].Status, gl.UserStatusActive, "first")
	expectEqual(t, users[1].Status, gl.UserStatusInactive, "second")
}

func TestListsOfObjects(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listUsers", object{"listUsers": list{userAliceJson, userBobJson}})
	users := must(h.client.Queries.ListUsers(h.ctx)).ListUsers
	expectEqual(t, len(users), 2, "length")
	expectEqual(t, users[0].Id, "user-1", "first id")
	expectEqual(t, users[1].Id, "user-2", "second id")

	h.adapter.RegisterData("listUsers", object{"listUsers": list{}})
	if empty := must(h.client.Queries.ListUsers(h.ctx)).ListUsers; empty == nil || len(empty) != 0 {
		t.Fatalf("expected an empty, non-nil list, got %v", empty)
	}

	h.adapter.RegisterData("listUsers", object{"listUsers": list{userAliceJson}})
	first := must(h.client.Queries.ListUsers(h.ctx)).ListUsers[0]
	expectEqual(t, first.Name, "Alice Smith", "name")
	expectEqual(t, first.Address.City, "Springfield", "city")
}

func TestListsOfScalarsOnAType(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	alice := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser
	if len(alice.Tags) != 2 || alice.Tags[0] != "admin" || alice.Tags[1] != "beta" {
		t.Fatalf("tags: %v", alice.Tags)
	}
	if len(alice.Scores) != 3 || alice.Scores[0] != 10 || alice.Scores[2] != 30 {
		t.Fatalf("scores: %v", alice.Scores)
	}
	h.adapter.RegisterData("getUser", object{"getUser": userBobJson})
	bob := must(h.client.Queries.GetUser(h.ctx, "user-2")).GetUser
	if len(bob.Tags) != 0 || bob.Scores != nil {
		t.Fatalf("tags=%v scores=%v", bob.Tags, bob.Scores)
	}
}

func TestListOfObjectsWithNullableFields(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getTags", object{"getTags": tagsJson})
	tags := must(h.client.Queries.GetTags(h.ctx)).GetTags
	expectEqual(t, len(tags), 2, "length")
	expectEqual(t, tags[0].Label, "dart", "label")
	if tags[0].Color == nil || *tags[0].Color != "#0175C2" || tags[1].Color != nil {
		t.Fatalf("colors: %v %v", tags[0].Color, tags[1].Color)
	}
}

func TestRequiredNestedObject(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	a := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser.Address
	expectEqual(t, a.Street, "123 Main St", "street")
	expectEqual(t, a.City, "Springfield", "city")
	expectEqual(t, a.Country, "US", "country")
	if a.Zip == nil || *a.Zip != "12345" {
		t.Fatalf("zip: %v", a.Zip)
	}
}

func TestNullableNestedObject(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	if b := must(h.client.Queries.GetUser(h.ctx, "user-1")).GetUser.BillingAddress; b != nil {
		t.Fatalf("expected nil, got %v", b)
	}
	h.adapter.RegisterData("getUser", object{"getUser": userBobJson})
	b := must(h.client.Queries.GetUser(h.ctx, "user-2")).GetUser.BillingAddress
	if b == nil || b.Street != "789 Pine Rd" || b.City != "Capital City" || *b.Zip != "99999" {
		t.Fatalf("billing address: %+v", b)
	}
	if zip := must(h.client.Queries.GetUser(h.ctx, "user-2")).GetUser.Address.Zip; zip != nil {
		t.Fatalf("expected nil zip, got %v", *zip)
	}
}

func TestMultiLevelNesting(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getPost", object{"getPost": postJson})
	post := must(h.client.Queries.GetPost(h.ctx, "post-1")).GetPost
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Email, "alice@test.com", "author email")
	expectEqual(t, post.Author.Address.City, "Springfield", "author city")
	expectEqual(t, post.Title, "Hello World", "title")
	expectEqual(t, post.ViewCount, 128, "viewCount")
	if post.CoAuthor != nil {
		t.Fatal("expected nil coAuthor")
	}
	h.adapter.RegisterData("getPost", object{"getPost": postWithCoAuthorJson})
	if co := must(h.client.Queries.GetPost(h.ctx, "post-2")).GetPost.CoAuthor; co == nil || co.Id != "user-2" {
		t.Fatalf("coAuthor: %+v", co)
	}
}

func TestSkipOnClientFieldIsIgnored(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getAuditEntry", object{"getAuditEntry": auditEntryWithExtraJson})
	entry := must(h.client.Queries.GetAuditEntry(h.ctx, "audit-2")).GetAuditEntry
	expectEqual(t, entry.Id, "audit-2", "id")
	expectEqual(t, entry.Action, "LOGOUT", "action")
}

func TestNullableQueryReturn(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("findUser", object{"findUser": nil})
	if u := must(h.client.Queries.FindUser(h.ctx, "missing")).FindUser; u != nil {
		t.Fatalf("expected nil, got %v", u)
	}
	h.adapter.RegisterData("findUser", object{"findUser": userAliceJson})
	if u := must(h.client.Queries.FindUser(h.ctx, "user-1")).FindUser; u == nil || u.Name != "Alice Smith" {
		t.Fatalf("user: %+v", u)
	}
}

func TestScalarFields(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getAllScalars", object{"getAllScalars": allScalarsNullJson})
	s := must(h.client.Queries.GetAllScalars(h.ctx, "scalar-1")).GetAllScalars
	expectEqual(t, s.Id, "scalar-1", "id")
	expectEqual(t, s.StrVal, "hello world", "strVal")
	expectEqual(t, s.IntVal, 42, "intVal")
	if s.FloatVal < 3.139 || s.FloatVal > 3.141 {
		t.Fatalf("floatVal: %v", s.FloatVal)
	}
	if !s.BoolVal {
		t.Fatal("boolVal should be true")
	}
	if s.NullableStr != nil || s.NullableInt != nil || s.NullableFloat != nil || s.NullableBool != nil || s.NullableId != nil {
		t.Fatalf("nullable scalars should be nil: %+v", s)
	}
	expectEqual(t, h.adapter.LastCall().Variables["id"].(string), "scalar-1", "id variable")
	expectEqual(t, h.adapter.LastCall().OperationName, "getAllScalars", "operation name")
}

func TestPresentScalarFields(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getAllScalars", object{"getAllScalars": allScalarsPresentJson})
	s := must(h.client.Queries.GetAllScalars(h.ctx, "scalar-2")).GetAllScalars
	if *s.NullableStr != "present" || *s.NullableInt != 99 || *s.NullableId != "nid-1" {
		t.Fatalf("scalars: %+v", s)
	}
	if *s.NullableFloat < 2.717 || *s.NullableFloat > 2.719 {
		t.Fatalf("nullableFloat: %v", *s.NullableFloat)
	}
	if s.NullableBool == nil || *s.NullableBool {
		t.Fatal("nullableBool should be a pointer to false")
	}
	expectEqual(t, s.IntVal, -1, "negative int")
	if s.FloatVal > -0.499 || s.FloatVal < -0.501 {
		t.Fatalf("negative float: %v", s.FloatVal)
	}
	if s.BoolVal {
		t.Fatal("boolVal should be false")
	}
}
