package tests

import (
	"testing"
	"time"
)

func TestCacheHitReturnsSameData(t *testing.T) {
	c := newClient(t)
	first := must(c.Queries.GetCachedUser(ctx(t), "user-1"))
	second := must(c.Queries.GetCachedUser(ctx(t), "user-1"))
	expectEqual(t, second.GetCachedUser.Id, first.GetCachedUser.Id, "id")
	expectEqual(t, second.GetCachedUser.Name, "Alice Smith", "name")
}

func TestDataAccessibleAfterTagInvalidation(t *testing.T) {
	c := newClient(t)
	must(c.Queries.GetCachedUser(ctx(t), "user-1"))
	must(c.Mutations.CreateCachedUser(ctx(t), minimalInput()))
	expectEqual(t, must(c.Queries.GetCachedUser(ctx(t), "user-1")).GetCachedUser.Name, "Alice Smith", "name")

	must(c.Queries.ListCachedUsers(ctx(t)))
	must(c.Mutations.CreateCachedUser(ctx(t), minimalInput()))
	if len(must(c.Queries.ListCachedUsers(ctx(t))).ListCachedUsers) == 0 {
		t.Fatal("expected cached users")
	}
}

func TestDataAccessibleAfterMultiTagInvalidation(t *testing.T) {
	c := newClient(t)
	must(c.Queries.GetCachedUser(ctx(t), "user-1"))
	must(c.Mutations.TransferPost(ctx(t), "post-1", "user-2"))
	expectEqual(t, must(c.Queries.GetCachedUser(ctx(t), "user-1")).GetCachedUser.Id, "user-1", "user id")

	must(c.Queries.GetCachedPost(ctx(t), "post-1"))
	must(c.Mutations.TransferPost(ctx(t), "post-1", "user-2"))
	expectEqual(t, must(c.Queries.GetCachedPost(ctx(t), "post-1")).GetCachedPost.Id, "post-1", "post id")
}

func TestResetAll(t *testing.T) {
	c := newClient(t)
	if !must(c.Mutations.ResetAll(ctx(t))).ResetAll {
		t.Fatal("expected true")
	}
	must(c.Queries.GetCachedUser(ctx(t), "user-1"))
	must(c.Mutations.ResetAll(ctx(t)))
	expectEqual(t, must(c.Queries.GetCachedUser(ctx(t), "user-1")).GetCachedUser.Name, "Alice Smith", "name")
}

func TestTtlExpiryRefetches(t *testing.T) {
	c := newClient(t)
	must(c.Queries.GetStaleUser(ctx(t), "user-1"))
	time.Sleep(2 * time.Second)
	res := must(c.Queries.GetStaleUser(ctx(t), "user-1"))
	if res.GetStaleUser == nil || res.GetStaleUser.Name != "Alice Smith" {
		t.Fatalf("stale user: %+v", res.GetStaleUser)
	}
}

func TestUncachedQueriesWorkOnRepeatedCalls(t *testing.T) {
	c := newClient(t)
	first := must(c.Queries.GetUser(ctx(t), "user-1"))
	second := must(c.Queries.GetUser(ctx(t), "user-1"))
	expectEqual(t, first.GetUser.Id, second.GetUser.Id, "id")
}
