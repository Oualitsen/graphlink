package tests

import (
	"testing"
	"time"
)

func TestCacheHit(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedUser", object{"getCachedUser": userAliceJson})
	first := must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	second := must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 1, "adapter calls")
	expectEqual(t, second.GetCachedUser.Id, first.GetCachedUser.Id, "id")
	expectEqual(t, second.GetCachedUser.Name, "Alice Smith", "name")
}

func TestCacheMissOnDifferentArgs(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedUser", object{"getCachedUser": userAliceJson})
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-2"))
	expectEqual(t, h.adapter.CallCount(), 2, "after two ids")
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 2, "third call is a hit")
}

func TestTagInvalidationByCreateCachedUser(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedUser", object{"getCachedUser": userAliceJson})
	h.adapter.RegisterData("createCachedUser", object{"createCachedUser": userAliceJson})
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 1, "hit")
	must(h.client.Mutations.CreateCachedUser(h.ctx, minimalInput()))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 3, "miss after invalidation")
}

func TestListCachedUsersInvalidatedBySameTag(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("listCachedUsers", object{"listCachedUsers": list{userAliceJson}})
	h.adapter.RegisterData("createCachedUser", object{"createCachedUser": userAliceJson})
	must(h.client.Queries.ListCachedUsers(h.ctx))
	must(h.client.Queries.ListCachedUsers(h.ctx))
	must(h.client.Mutations.CreateCachedUser(h.ctx, minimalInput()))
	must(h.client.Queries.ListCachedUsers(h.ctx))
	expectEqual(t, h.adapter.CallCount(), 3, "adapter calls")
}

func TestMultiTagInvalidationByTransferPost(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedUser", object{"getCachedUser": userAliceJson})
	h.adapter.RegisterData("getCachedPost", object{"getCachedPost": postJson})
	h.adapter.RegisterData("transferPost", object{"transferPost": postJson})
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedPost(h.ctx, "post-1"))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedPost(h.ctx, "post-1"))
	expectEqual(t, h.adapter.CallCount(), 2, "both cached")
	must(h.client.Mutations.TransferPost(h.ctx, "post-1", "user-2"))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedPost(h.ctx, "post-1"))
	expectEqual(t, h.adapter.CallCount(), 5, "both miss after transferPost")
}

func TestConfigWithoutSharedTagIsNotInvalidated(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedConfig", object{"getCachedConfig": allScalarsNullJson})
	h.adapter.RegisterData("transferPost", object{"transferPost": postJson})
	must(h.client.Queries.GetCachedConfig(h.ctx))
	must(h.client.Mutations.TransferPost(h.ctx, "post-1", "user-2"))
	must(h.client.Queries.GetCachedConfig(h.ctx))
	expectEqual(t, h.adapter.CallCount(), 2, "adapter calls")
}

func TestInvalidateAllByResetAll(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getCachedUser", object{"getCachedUser": userAliceJson})
	h.adapter.RegisterData("getCachedPost", object{"getCachedPost": postJson})
	h.adapter.RegisterData("getCachedConfig", object{"getCachedConfig": allScalarsNullJson})
	h.adapter.RegisterData("resetAll", object{"resetAll": true})
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedPost(h.ctx, "post-1"))
	must(h.client.Queries.GetCachedConfig(h.ctx))
	must(h.client.Mutations.ResetAll(h.ctx))
	must(h.client.Queries.GetCachedUser(h.ctx, "user-1"))
	must(h.client.Queries.GetCachedPost(h.ctx, "post-1"))
	must(h.client.Queries.GetCachedConfig(h.ctx))
	expectEqual(t, h.adapter.CallCount(), 7, "adapter calls")
}

func TestResetAllReturnsTrue(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("resetAll", object{"resetAll": true})
	if !must(h.client.Mutations.ResetAll(h.ctx)).ResetAll {
		t.Fatal("expected true")
	}
}

func TestTtlExpiryRefetches(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getStaleUser", object{"getStaleUser": userAliceJson})
	must(h.client.Queries.GetStaleUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 1, "first call")
	time.Sleep(2 * time.Second)
	must(h.client.Queries.GetStaleUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 2, "after ttl")
}

func TestStaleIfOfflineReturnsStaleValueWhenNetworkFails(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getStaleUser", object{"getStaleUser": userAliceJson})
	must(h.client.Queries.GetStaleUser(h.ctx, "user-1"))
	time.Sleep(2 * time.Second)
	h.adapter.SimulateFailure = true
	res := must(h.client.Queries.GetStaleUser(h.ctx, "user-1"))
	if res.GetStaleUser == nil || res.GetStaleUser.Name != "Alice Smith" {
		t.Fatalf("unexpected stale value: %+v", res.GetStaleUser)
	}
	expectEqual(t, h.adapter.CallCount(), 1, "no new recorded call")
}

func TestStaleIfOfflineThrowsWithoutStaleValue(t *testing.T) {
	h := newHarness(t)
	h.adapter.SimulateFailure = true
	if _, err := h.client.Queries.GetStaleUser(h.ctx, "user-1"); err == nil {
		t.Fatal("expected an error")
	}
}

func TestUncachedQueriesAlwaysHitTheAdapter(t *testing.T) {
	h := newHarness(t)
	h.adapter.RegisterData("getUser", object{"getUser": userAliceJson})
	must(h.client.Queries.GetUser(h.ctx, "user-1"))
	must(h.client.Queries.GetUser(h.ctx, "user-1"))
	expectEqual(t, h.adapter.CallCount(), 2, "adapter calls")
}
