import unittest

from generated import (
    AddressInput,
    ClassInput,
    CreateUserInput,
    CreateWithDefaultsInput,
    EventType,
    GetDriverFieldArgs,
    NestedDefaultsInput,
    NormalizedInput,
    Priority,
    Role,
    UpdateUserInput,
    UserStatus,
)

from .real_server import new_client

ADDRESS = AddressInput(street="123 Main St", city="Springfield", country="US")
MINIMAL = CreateUserInput(name="Alice Smith", email="alice@test.com", status=UserStatus.ACTIVE, address=ADDRESS)


class MutationsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_create_user_echoes_input(self) -> None:
        user = (await self.client.mutations.create_user(input=MINIMAL)).create_user
        self.assertEqual((user.name, user.email), ("Alice Smith", "alice@test.com"))
        self.assertIs(user.status, UserStatus.ACTIVE)
        self.assertIsNone(user.priority)
        self.assertEqual((user.address.street, user.address.city), ("123 Main St", "Springfield"))
        self.assertIsNone(user.address.zip)
        self.assertIsNone(user.billing_address)
        self.assertEqual(user.tags, [])

    async def test_create_user_optional_fields(self) -> None:
        full = CreateUserInput(
            name="Alice",
            email="a@b.com",
            status=UserStatus.SUSPENDED,
            priority=Priority.CRITICAL,
            address=AddressInput(street="123 Main St", city="Springfield", country="US", zip="12345"),
            tags=["admin", "beta"],
        )
        user = (await self.client.mutations.create_user(input=full)).create_user
        self.assertIs(user.status, UserStatus.SUSPENDED)
        self.assertIs(user.priority, Priority.CRITICAL)
        self.assertEqual(user.address.zip, "12345")
        self.assertEqual(user.tags, ["admin", "beta"])

    async def test_delete_user(self) -> None:
        self.assertIs((await self.client.mutations.delete_user(id="user-1")).delete_user, True)

    async def test_update_user_preserves_other_fields(self) -> None:
        res = await self.client.mutations.update_user(id="user-1", input=UpdateUserInput(name="Updated Alice"))
        self.assertEqual((res.update_user.id, res.update_user.name), ("user-1", "Updated Alice"))
        self.assertEqual(res.update_user.email, "alice@test.com")
        self.assertIs(res.update_user.status, UserStatus.ACTIVE)
        self.assertEqual(res.update_user.address.street, "123 Main St")

    async def test_update_user_status(self) -> None:
        res = await self.client.mutations.update_user(id="user-1", input=UpdateUserInput(status=UserStatus.SUSPENDED))
        self.assertIs(res.update_user.status, UserStatus.SUSPENDED)
        res = await self.client.mutations.update_user(id="user-2", input=UpdateUserInput(status=UserStatus.ACTIVE))
        self.assertEqual((res.update_user.id, res.update_user.status), ("user-2", UserStatus.ACTIVE))


class CacheTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_cache_and_invalidation_keep_data_accessible(self) -> None:
        first = await self.client.queries.get_cached_user(id="user-1")
        second = await self.client.queries.get_cached_user(id="user-1")
        self.assertEqual(second.get_cached_user.id, first.get_cached_user.id)
        await self.client.mutations.create_cached_user(input=MINIMAL)
        self.assertEqual((await self.client.queries.get_cached_user(id="user-1")).get_cached_user.name, "Alice Smith")
        self.assertTrue((await self.client.queries.list_cached_users()).list_cached_users)
        await self.client.queries.get_cached_post(id="post-1")
        await self.client.mutations.transfer_post(post_id="post-1", new_author_id="user-2")
        self.assertEqual((await self.client.queries.get_cached_post(id="post-1")).get_cached_post.id, "post-1")

    async def test_reset_all(self) -> None:
        await self.client.queries.get_cached_user(id="user-1")
        self.assertIs((await self.client.mutations.reset_all()).reset_all, True)
        self.assertEqual((await self.client.queries.get_cached_user(id="user-1")).get_cached_user.name, "Alice Smith")

    async def test_ttl_expiry(self) -> None:
        import asyncio

        await self.client.queries.get_stale_user(id="user-1")
        await asyncio.sleep(2)
        self.assertEqual((await self.client.queries.get_stale_user(id="user-1")).get_stale_user.name, "Alice Smith")


class DefaultValuesTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_input_field_defaults(self) -> None:
        res = (await self.client.mutations.create_with_defaults(input=CreateWithDefaultsInput(name="test"))).create_with_defaults
        self.assertIs(res.role, Role.USER)
        self.assertEqual(res.age, 18)
        self.assertIs(res.is_active, True)
        self.assertEqual(res.score, 4.5)
        self.assertEqual(res.nickname, "anonymous")
        self.assertEqual(res.tags, ["dart", "graphql"])
        self.assertEqual(res.name, "test")

    async def test_explicit_values_override_defaults(self) -> None:
        override = CreateWithDefaultsInput(
            name="override-test", role=Role.ADMIN, age=99, is_active=False, score=9.9, nickname="custom", tags=["custom-tag"]
        )
        res = (await self.client.mutations.create_with_defaults(input=override)).create_with_defaults
        self.assertEqual((res.name, res.age, res.score, res.nickname, res.tags), ("override-test", 99, 9.9, "custom", ["custom-tag"]))
        self.assertIs(res.role, Role.ADMIN)
        self.assertIs(res.is_active, False)

    async def test_argument_defaults(self) -> None:
        self.assertTrue((await self.client.queries.list_users_with_defaults()).list_users_with_defaults)
        self.assertEqual(len((await self.client.queries.list_users_with_defaults(limit=1)).list_users_with_defaults), 1)
        self.assertTrue((await self.client.queries.list_users_with_defaults(role=Role.ADMIN)).list_users_with_defaults)

    async def test_nested_object_and_list_defaults(self) -> None:
        res = (await self.client.mutations.create_with_nested_defaults(input=NestedDefaultsInput(name="nested-test"))).create_with_nested_defaults
        self.assertEqual(res.name, "nested-test")
        a = res.address
        self.assertEqual((a.street, a.city, a.country, a.zip), ("123 Main St", "Springfield", "US", "12345"))
        self.assertEqual(len(res.contacts), 2)
        self.assertEqual((res.contacts[0].street, res.contacts[0].city, res.contacts[0].zip), ("456 Oak Ave", "Shelbyville", None))
        self.assertEqual((res.contacts[1].street, res.contacts[1].city, res.contacts[1].zip), ("789 Pine Rd", "Capital City", "99999"))
        self.assertEqual(len(res.matrix), 2)
        self.assertEqual((res.matrix[0][0].street, res.matrix[0][0].city, res.matrix[0][0].country, res.matrix[0][0].zip), ("1st St", "Paris", "FR", "75000"))
        self.assertEqual((res.matrix[1][0].street, res.matrix[1][0].city, res.matrix[1][0].zip), ("2nd St", "Lyon", "69000"))

    async def test_explicit_nested_values_override(self) -> None:
        override = NestedDefaultsInput(
            name="override-nested",
            address=AddressInput(street="Custom St", city="Custom City", country="XX"),
            contacts=[AddressInput(street="One", city="Two", country="Three", zip="44444")],
            matrix=[[AddressInput(street="A", city="B", country="C")]],
        )
        res = (await self.client.mutations.create_with_nested_defaults(input=override)).create_with_nested_defaults
        self.assertEqual((res.address.street, res.address.zip), ("Custom St", None))
        self.assertEqual(len(res.contacts), 1)
        self.assertEqual(res.contacts[0].street, "One")
        self.assertEqual(res.matrix[0][0].street, "A")

    async def test_field_argument_defaults(self) -> None:
        res = (await self.client.queries.get_driver(id="driver-1", field_args=GetDriverFieldArgs(last_used_millage_odometer_km=100))).get_driver
        self.assertEqual(res.last_used_millage, 100)
        res = (await self.client.queries.get_driver(id="driver-1", field_args=GetDriverFieldArgs(last_used_millage_odometer_km=200))).get_driver
        self.assertEqual(res.last_used_fuel, 4)
        explicit = GetDriverFieldArgs(last_used_millage_odometer_km=500, last_used_fuel_liters=25)
        res = (await self.client.queries.get_driver(id="driver-1", field_args=explicit)).get_driver
        self.assertEqual((res.last_used_millage, res.last_used_fuel), (500, 25))


class KeywordAndNormalizationTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_keyword_query_and_argument(self) -> None:
        res = await self.client.queries.class_(class_="abc")
        self.assertEqual(res.class_.id, "abc")
        self.assertEqual(res.class_.class_, "class-of-abc")

    async def test_keyword_input_field(self) -> None:
        res = await self.client.mutations.make_class(input=ClassInput(class_="hello"))
        self.assertEqual((res.make_class.id, res.make_class.class_), ("made", "hello"))

    async def test_enum_wire_names(self) -> None:
        self.assertEqual(EventType.PENDING.to_json(), "pending")
        self.assertEqual(EventType.IN_PROGRESS.to_json(), "in_progress")
        self.assertIs(EventType.from_json("completed_ok"), EventType.COMPLETED_OK)

    async def test_field_normalization(self) -> None:
        record = (await self.client.queries.get_normalized_record(id="rec-1")).get_normalized_record
        self.assertEqual((record.first_name, record.last_name, record.user_age), ("Alice", "Smith", 30))
        self.assertIs(record.event_type, EventType.IN_PROGRESS)

    async def test_input_normalization_round_trip(self) -> None:
        sent = NormalizedInput(first_name="Bob", last_name="Jones", event_type=EventType.COMPLETED_OK)
        record = (await self.client.mutations.create_normalized_record(input=sent)).create_normalized_record
        self.assertEqual((record.first_name, record.last_name), ("Bob", "Jones"))
        self.assertIs(record.event_type, EventType.COMPLETED_OK)


if __name__ == "__main__":
    unittest.main()
