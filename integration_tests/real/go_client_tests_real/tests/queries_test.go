package tests

import (
	"testing"

	gl "graphlink.dev/realtests/generated"
)

func TestFetchUserAndPost(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.FetchUserAndPost(ctx(t), "user-1", "post-1"))
	expectEqual(t, res.User.Name, "Alice Smith", "user name")
	expectEqual(t, res.User.Id, "user-1", "user id")
	expectEqual(t, res.Post.Title, "Hello World", "post title")
	expectEqual(t, res.Post.Author.Id, "user-1", "post author")
}

func TestFetchUserSummaryProjectedType(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.FetchUserSummary(ctx(t), "user-1"))
	expectEqual(t, res.GetUser.Id, "user-1", "id")
	expectEqual(t, res.GetUser.Name, "Alice Smith", "name")
	expectEqual(t, res.GetUser.Status, gl.UserStatusActive, "status")
}

func TestFetchCachedPairDataCorrectness(t *testing.T) {
	c := newClient(t)
	must(c.Queries.FetchCachedPair(ctx(t), "user-1", "post-1"))
	res := must(c.Queries.FetchCachedPair(ctx(t), "user-1", "post-1"))
	expectEqual(t, res.User.Name, "Alice Smith", "user name")
	expectEqual(t, res.Post.Title, "Hello World", "post title")
}

func TestRunSearchUnionDispatch(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.RunSearch(ctx(t), "test"))
	expectEqual(t, len(res.Search), 2, "length")
	user, ok := res.Search[0].(gl.UserResult)
	if !ok || user.Name != "Alice Smith" {
		t.Fatalf("first element: %#v", res.Search[0])
	}
	post, ok := res.Search[1].(gl.PostResult)
	if !ok || post.Title != "Hello World" {
		t.Fatalf("second element: %#v", res.Search[1])
	}
}

func TestCycleUserPostsUser(t *testing.T) {
	c := newClient(t)
	user := must(c.Queries.GetUser(ctx(t), "user-with-posts")).GetUser
	expectEqual(t, len(user.Posts), 4, "posts")
	post := user.Posts[0]
	expectEqual(t, post.Id, "post-10", "post id")
	expectEqual(t, post.Title, "Cyclic Post", "title")
	expectEqual(t, post.ViewCount, 7, "viewCount")
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Name, "Alice Smith", "author name")
	expectEqual(t, post.Author.Address.City, "Springfield", "author city")
	if posts := must(c.Queries.GetUser(ctx(t), "user-1")).GetUser.Posts; posts != nil {
		t.Fatalf("expected nil posts for Alice, got %v", posts)
	}
}

func TestCyclePostAuthorPost(t *testing.T) {
	c := newClient(t)
	post := must(c.Queries.GetPost(ctx(t), "post-10")).GetPost
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Name, "Alice Smith", "author name")
	expectEqual(t, post.Author.Email, "alice@test.com", "author email")
	if len(post.Author.Tags) != 1 || post.Author.Tags[0] != "admin" {
		t.Fatalf("tags: %v", post.Author.Tags)
	}
}

func TestEnumDeserialization(t *testing.T) {
	c := newClient(t)
	alice := must(c.Queries.GetUser(ctx(t), "user-1")).GetUser
	expectEqual(t, alice.Status, gl.UserStatusActive, "alice status")
	if alice.Priority == nil || *alice.Priority != gl.PriorityHigh {
		t.Fatalf("priority: %v", alice.Priority)
	}
	bob := must(c.Queries.GetUser(ctx(t), "user-2")).GetUser
	expectEqual(t, bob.Status, gl.UserStatusInactive, "bob status")
	if bob.Priority != nil {
		t.Fatalf("expected nil priority, got %v", *bob.Priority)
	}
}

func TestEnumSerializationInQueryVariables(t *testing.T) {
	c := newClient(t)
	active := must(c.Queries.ListUsersByStatus(ctx(t), gl.UserStatusActive)).ListUsersByStatus
	if len(active) == 0 {
		t.Fatal("expected active users")
	}
	for _, u := range active {
		expectEqual(t, u.Status, gl.UserStatusActive, "active user status")
	}
	inactive := must(c.Queries.ListUsersByStatus(ctx(t), gl.UserStatusInactive)).ListUsersByStatus
	if len(inactive) == 0 {
		t.Fatal("expected inactive users")
	}
	for _, u := range inactive {
		expectEqual(t, u.Status, gl.UserStatusInactive, "inactive user status")
	}
	if suspended := must(c.Queries.ListUsersByStatus(ctx(t), gl.UserStatusSuspended)).ListUsersByStatus; len(suspended) != 0 {
		t.Fatalf("expected no suspended users, got %d", len(suspended))
	}
	statuses := map[gl.UserStatus]bool{}
	for _, u := range must(c.Queries.ListUsers(ctx(t))).ListUsers {
		statuses[u.Status] = true
	}
	if !statuses[gl.UserStatusActive] || !statuses[gl.UserStatusInactive] {
		t.Fatalf("statuses: %v", statuses)
	}
}

func TestLists(t *testing.T) {
	c := newClient(t)
	users := must(c.Queries.ListUsers(ctx(t))).ListUsers
	expectEqual(t, len(users), 2, "users")
	expectEqual(t, users[0].Id, "user-1", "first id")
	expectEqual(t, users[1].Id, "user-2", "second id")
	expectEqual(t, users[0].Name, "Alice Smith", "name")
	expectEqual(t, users[0].Address.City, "Springfield", "city")

	alice := must(c.Queries.GetUser(ctx(t), "user-1")).GetUser
	if len(alice.Tags) != 2 || alice.Tags[0] != "admin" || alice.Tags[1] != "beta" {
		t.Fatalf("tags: %v", alice.Tags)
	}
	if len(alice.Scores) != 3 || alice.Scores[0] != 10 || alice.Scores[2] != 30 {
		t.Fatalf("scores: %v", alice.Scores)
	}
	bob := must(c.Queries.GetUser(ctx(t), "user-2")).GetUser
	if len(bob.Tags) != 0 || bob.Scores != nil {
		t.Fatalf("tags=%v scores=%v", bob.Tags, bob.Scores)
	}

	tags := must(c.Queries.GetTags(ctx(t))).GetTags
	expectEqual(t, len(tags), 2, "tags")
	expectEqual(t, tags[0].Label, "dart", "label")
	if tags[0].Color == nil || *tags[0].Color != "#0175C2" || tags[1].Color != nil {
		t.Fatalf("colors: %v %v", tags[0].Color, tags[1].Color)
	}
}

func TestNestingAndNullability(t *testing.T) {
	c := newClient(t)
	alice := must(c.Queries.GetUser(ctx(t), "user-1")).GetUser
	expectEqual(t, alice.Address.Street, "123 Main St", "street")
	expectEqual(t, alice.Address.Country, "US", "country")
	expectEqual(t, *alice.Address.Zip, "12345", "zip")
	if alice.BillingAddress != nil {
		t.Fatal("Alice has no billing address")
	}
	bob := must(c.Queries.GetUser(ctx(t), "user-2")).GetUser
	b := bob.BillingAddress
	if b == nil || b.Street != "789 Pine Rd" || b.City != "Capital City" || *b.Zip != "99999" {
		t.Fatalf("billing address: %+v", b)
	}
	if bob.Address.Zip != nil {
		t.Fatal("Bob's address has no zip")
	}

	post := must(c.Queries.GetPost(ctx(t), "post-1")).GetPost
	expectEqual(t, post.Author.Id, "user-1", "author id")
	expectEqual(t, post.Author.Email, "alice@test.com", "author email")
	expectEqual(t, post.Author.Address.City, "Springfield", "author city")
	expectEqual(t, post.Title, "Hello World", "title")
	expectEqual(t, post.ViewCount, 128, "viewCount")
	if post.CoAuthor != nil {
		t.Fatal("post-1 has no coAuthor")
	}
	if co := must(c.Queries.GetPost(ctx(t), "post-2")).GetPost.CoAuthor; co == nil || co.Id != "user-2" {
		t.Fatalf("coAuthor: %+v", co)
	}

	if u := must(c.Queries.FindUser(ctx(t), "missing")).FindUser; u != nil {
		t.Fatalf("expected nil, got %+v", u)
	}
	if u := must(c.Queries.FindUser(ctx(t), "user-1")).FindUser; u == nil || u.Name != "Alice Smith" {
		t.Fatalf("user: %+v", u)
	}

	entry := must(c.Queries.GetAuditEntry(ctx(t), "audit-2")).GetAuditEntry
	expectEqual(t, entry.Id, "audit-2", "audit id")
	expectEqual(t, entry.Action, "LOGOUT", "audit action")
}

func TestScalars(t *testing.T) {
	c := newClient(t)
	s := must(c.Queries.GetAllScalars(ctx(t), "scalar-1")).GetAllScalars
	expectEqual(t, s.Id, "scalar-1", "id")
	expectEqual(t, s.StrVal, "hello world", "strVal")
	expectEqual(t, s.IntVal, 42, "intVal")
	if s.FloatVal < 3.139 || s.FloatVal > 3.141 || !s.BoolVal {
		t.Fatalf("scalars: %+v", s)
	}
	if s.NullableStr != nil || s.NullableInt != nil || s.NullableFloat != nil || s.NullableBool != nil || s.NullableId != nil {
		t.Fatalf("nullable scalars should be nil: %+v", s)
	}
	p := must(c.Queries.GetAllScalars(ctx(t), "scalar-2")).GetAllScalars
	if *p.NullableStr != "present" || *p.NullableInt != 99 || *p.NullableId != "nid-1" {
		t.Fatalf("present scalars: %+v", p)
	}
	if *p.NullableFloat < 2.717 || *p.NullableFloat > 2.719 || p.NullableBool == nil || *p.NullableBool {
		t.Fatalf("present scalars: %+v", p)
	}
	expectEqual(t, p.IntVal, -1, "negative int")
	if p.FloatVal > -0.499 || p.FloatVal < -0.501 || p.BoolVal {
		t.Fatalf("scalars: %+v", p)
	}
}

func TestLiteralArgumentsAgainstTheRealServer(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.FindFirstUser(ctx(t)))
	expectEqual(t, res.FindUser.Name, "Alice Smith", "name")
	expectEqual(t, res.FindUser.Email, "alice@test.com", "email")

	active := must(c.Queries.ListActiveUsers(ctx(t))).ListUsersByStatus
	if len(active) != 1 || active[0].Id != "user-1" {
		t.Fatalf("active users: %+v", active)
	}
	alice := must(c.Queries.SearchAlice(ctx(t))).SearchUsers
	if len(alice) != 1 || alice[0].Name != "Alice Smith" {
		t.Fatalf("searchAlice: %+v", alice)
	}
	expectEqual(t, len(must(c.Queries.SearchWithFixedLimit(ctx(t), "s")).SearchUsers), 1, "searchWithFixedLimit")
	expectEqual(t, len(must(c.Queries.SearchPrice(ctx(t))).SearchUsers), 0, "searchPrice")
}

func TestKeywordsRoundTrip(t *testing.T) {
	c := newClient(t)
	res := must(c.Queries.Class(ctx(t), "abc"))
	expectEqual(t, res.Class.Id, "abc", "id")
	expectEqual(t, res.Class.Class, "class-of-abc", "class field")
	made := must(c.Mutations.MakeClass(ctx(t), gl.ClassInput{Class: "hello"}))
	expectEqual(t, made.MakeClass.Id, "made", "id")
	expectEqual(t, made.MakeClass.Class, "hello", "class")
}

func TestVehicleDriverExpansion(t *testing.T) {
	c := newClient(t)
	one := must(c.Queries.GetVehicleDriver(ctx(t), "vd-1")).GetVehicleDriver
	expectEqual(t, one.Id, "vd-1", "id")
	expectEqual(t, one.Name, "Alex Driver", "name")
	car, ok := one.Vehicle.(gl.Car)
	if !ok || car.Model != "Tesla Model 3" {
		t.Fatalf("vehicle: %#v", one.Vehicle)
	}
	owner := one.Vehicle.GetOwner()
	if owner == nil || owner.Id != "vo-1" || owner.Name != "Alice Owner" {
		t.Fatalf("owner: %+v", owner)
	}
	if owner.Driver == nil || owner.Driver.Id != "vd-1" || owner.Driver.Name != "Alex Driver" {
		t.Fatalf("owner.driver: %+v", owner.Driver)
	}
	if owner.Driver.Vehicle != nil {
		t.Fatal("expansion must stop at depth 3")
	}

	two := must(c.Queries.GetVehicleDriver(ctx(t), "vd-2")).GetVehicleDriver
	bike, ok := two.Vehicle.(gl.Bike)
	if !ok || bike.Brand != "Trek FX3" {
		t.Fatalf("vehicle: %#v", two.Vehicle)
	}
	owner = two.Vehicle.GetOwner()
	if owner == nil || owner.Id != "vo-2" || owner.Name != "Bob Owner" || owner.Driver.Vehicle != nil {
		t.Fatalf("owner: %+v", owner)
	}
}

func TestNormalization(t *testing.T) {
	c := newClient(t)
	for wire, value := range map[string]gl.EventType{
		"pending": gl.EventTypePending, "in_progress": gl.EventTypeInProgress, "completed_ok": gl.EventTypeCompletedOk,
	} {
		expectEqual(t, string(value), wire, "wire value")
	}
	rec := must(c.Queries.GetNormalizedRecord(ctx(t), "rec-1")).GetNormalizedRecord
	expectEqual(t, rec.FirstName, "Alice", "firstName")
	expectEqual(t, rec.LastName, "Smith", "lastName")
	expectEqual(t, rec.UserAge, 30, "userAge")
	expectEqual(t, rec.EventType, gl.EventTypeInProgress, "eventType")
	created := must(c.Mutations.CreateNormalizedRecord(ctx(t), gl.NormalizedInput{FirstName: "Bob", LastName: "Jones", EventType: gl.EventTypeCompletedOk})).CreateNormalizedRecord
	expectEqual(t, created.FirstName, "Bob", "firstName")
	expectEqual(t, created.LastName, "Jones", "lastName")
	expectEqual(t, created.EventType, gl.EventTypeCompletedOk, "eventType")
}
