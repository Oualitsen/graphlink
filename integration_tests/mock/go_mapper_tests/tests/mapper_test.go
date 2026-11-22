package tests

import (
	"testing"

	"graphlink.dev/mappertests/generated"
	"graphlink.dev/mappertests/persistence"
)

func entity() persistence.UserEntity {
	return persistence.UserEntity{
		Id:        "1",
		FullName:  "Ada Lovelace",
		Addresses: []persistence.AddressEntity{{Street: "Main"}, {Street: "Side"}},
		Home:      &persistence.AddressEntity{Street: "Home"},
	}
}

func TestExternalSourceCopiesFieldsAndMapsListAndNestedValue(t *testing.T) {
	user := generated.UserEntityMapper{}.ToUser(entity(), "anon")
	if user.Id != "1" || user.FullName != "Ada Lovelace" {
		t.Fatalf("fields: %+v", user)
	}
	if len(user.Addresses) != 2 || user.Addresses[0].Street != "Main" || user.Addresses[1].Street != "Side" {
		t.Fatalf("list: %+v", user.Addresses)
	}
	if user.Home == nil || user.Home.Street != "Home" {
		t.Fatalf("nested: %+v", user.Home)
	}
}

func TestExternalSourceNullTakesTheDefaultAndAPresentValueWins(t *testing.T) {
	if nick := (generated.UserEntityMapper{}.ToUser(entity(), "anon")).Nick; nick != "anon" {
		t.Fatalf("default: %q", nick)
	}
	bee := "bee"
	other := persistence.UserEntity{Id: "2", FullName: "B", Nick: &bee}
	user := generated.UserEntityMapper{}.ToUser(other, "anon")
	if user.Nick != "bee" || user.Home != nil || len(user.Addresses) != 0 {
		t.Fatalf("present value: %+v", user)
	}
}

func TestExternalTargetIsBuiltWithNestedValues(t *testing.T) {
	user := generated.UserEntityMapper{}.ToUser(entity(), "anon")
	back := generated.UserMapper{}.ToUserEntity(user)
	if back.Id != "1" || back.FullName != "Ada Lovelace" || back.Nick == nil || *back.Nick != "anon" {
		t.Fatalf("fields: %+v", back)
	}
	if len(back.Addresses) != 2 || back.Addresses[1].Street != "Side" {
		t.Fatalf("list: %+v", back.Addresses)
	}
	if back.Home == nil || back.Home.Street != "Home" {
		t.Fatalf("nested: %+v", back.Home)
	}
}

func TestExternalTargetKeepsANullNestedValueNull(t *testing.T) {
	user := generated.UserEntityMapper{}.ToUser(persistence.UserEntity{Id: "3", FullName: "C"}, "n")
	back := generated.UserMapper{}.ToUserEntity(user)
	if back.Home != nil {
		t.Fatal("home should be nil")
	}
}

func TestMapperStyleClassRenamesAFieldForOneTarget(t *testing.T) {
	user := generated.UserEntityMapper{}.ToUser(entity(), "anon")
	summary := generated.UserMapper{}.ToUserSummary(user)
	if summary.Id != "1" || summary.Name != "Ada Lovelace" {
		t.Fatalf("summary: %+v", summary)
	}
}
