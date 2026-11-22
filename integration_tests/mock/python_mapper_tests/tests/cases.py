import unittest

from persistence import AddressEntity, UserEntity


def entity() -> UserEntity:
    return UserEntity(
        id="1",
        full_name="Ada Lovelace",
        nick=None,
        addresses=[AddressEntity(street="Main"), AddressEntity(street="Side")],
        home=AddressEntity(street="Home"),
    )


class ExternalSourceTest:
    def test_copies_fields_and_maps_list_and_nested_value(self):
        user = self.mappers.UserEntityMapper.to_user(entity(), default_nick="anon")
        self.assertEqual(user.id, "1")
        self.assertEqual(user.full_name, "Ada Lovelace")
        self.assertEqual([a.street for a in user.addresses], ["Main", "Side"])
        self.assertEqual(user.home.street, "Home")

    def test_null_takes_the_default_and_a_present_value_wins(self):
        self.assertEqual(self.mappers.UserEntityMapper.to_user(entity(), default_nick="anon").nick, "anon")
        other = UserEntity(id="2", full_name="B", nick="bee", addresses=[], home=None)
        user = self.mappers.UserEntityMapper.to_user(other, default_nick="anon")
        self.assertEqual(user.nick, "bee")
        self.assertIsNone(user.home)
        self.assertEqual(user.addresses, [])


class ExternalTargetTest:
    def test_builds_the_external_class_with_nested_values(self):
        user = self.mappers.UserEntityMapper.to_user(entity(), default_nick="anon")
        back = self.mappers.UserMapper.to_user_entity(user)
        self.assertIsInstance(back, UserEntity)
        self.assertEqual(back.id, "1")
        self.assertEqual(back.full_name, "Ada Lovelace")
        self.assertEqual(back.nick, "anon")
        self.assertEqual([a.street for a in back.addresses], ["Main", "Side"])
        self.assertEqual(back.home.street, "Home")

    def test_a_null_nested_value_stays_null(self):
        bare = UserEntity(id="3", full_name="C", addresses=[], home=None)
        user = self.mappers.UserEntityMapper.to_user(bare, default_nick="n")
        self.assertIsNone(self.mappers.UserMapper.to_user_entity(user).home)


class MapperStyleClassTest:
    def test_renames_a_field_for_one_target(self):
        user = self.mappers.UserEntityMapper.to_user(entity(), default_nick="anon")
        summary = self.mappers.UserMapper.to_user_summary(user)
        self.assertEqual(summary.id, "1")
        self.assertEqual(summary.name, "Ada Lovelace")

    def test_the_generated_type_has_no_inline_to_method(self):
        user = self.mappers.UserEntityMapper.to_user(entity(), default_nick="anon")
        self.assertFalse(hasattr(user, "to_user_summary"))



def build(mappers):
    """TestCase classes bound to one generated flavor (client, FastAPI, Django)."""
    return [
        type(base.__name__, (base, unittest.TestCase), {"mappers": mappers})
        for base in (ExternalSourceTest, ExternalTargetTest, MapperStyleClassTest)
    ]
