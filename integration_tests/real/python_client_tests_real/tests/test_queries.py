import unittest

from generated import Car, Bike, GraphLinkException, PostResult, Priority, UserResult, UserStatus

from .real_server import new_client


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()


class ScalarsTest(RealTestCase):
    async def test_non_nullable_and_null_scalars(self) -> None:
        res = (await self.client.queries.get_all_scalars(id="scalar-1")).get_all_scalars
        self.assertEqual((res.id, res.str_val, res.int_val, res.bool_val), ("scalar-1", "hello world", 42, True))
        self.assertAlmostEqual(res.float_val, 3.14, places=3)
        for name in ("nullable_str", "nullable_int", "nullable_float", "nullable_bool", "nullable_id"):
            self.assertIsNone(getattr(res, name), name)

    async def test_present_scalars(self) -> None:
        res = (await self.client.queries.get_all_scalars(id="scalar-2")).get_all_scalars
        self.assertEqual((res.nullable_str, res.nullable_int, res.nullable_id), ("present", 99, "nid-1"))
        self.assertAlmostEqual(res.nullable_float, 2.718, places=3)
        self.assertIs(res.nullable_bool, False)
        self.assertEqual(res.int_val, -1)
        self.assertAlmostEqual(res.float_val, -0.5, places=3)
        self.assertIs(res.bool_val, False)


class NullabilityAndNestingTest(RealTestCase):
    async def test_query_returns(self) -> None:
        self.assertEqual((await self.client.queries.get_user(id="user-1")).get_user.id, "user-1")
        self.assertIsNone((await self.client.queries.find_user(id="missing")).find_user)
        self.assertEqual((await self.client.queries.find_user(id="user-1")).find_user.name, "Alice Smith")

    async def test_nested_objects(self) -> None:
        alice = (await self.client.queries.get_user(id="user-1")).get_user
        bob = (await self.client.queries.get_user(id="user-2")).get_user
        self.assertEqual((alice.address.street, alice.address.city, alice.address.zip), ("123 Main St", "Springfield", "12345"))
        self.assertIsNone(alice.billing_address)
        self.assertEqual((bob.billing_address.street, bob.billing_address.city, bob.billing_address.zip), ("789 Pine Rd", "Capital City", "99999"))
        self.assertIsNone(bob.address.zip)

    async def test_nullable_lists(self) -> None:
        alice = (await self.client.queries.get_user(id="user-1")).get_user
        bob = (await self.client.queries.get_user(id="user-2")).get_user
        self.assertEqual(alice.scores, [10, 20, 30])
        self.assertIsNone(bob.scores)
        self.assertEqual(alice.tags, ["admin", "beta"])
        self.assertEqual(bob.tags, [])

    async def test_multi_level_nesting(self) -> None:
        post = (await self.client.queries.get_post(id="post-1")).get_post
        self.assertEqual((post.title, post.view_count), ("Hello World", 128))
        self.assertEqual((post.author.id, post.author.name, post.author.email), ("user-1", "Alice Smith", "alice@test.com"))
        self.assertEqual(post.author.address.city, "Springfield")
        self.assertIsNone(post.co_author)
        self.assertEqual((await self.client.queries.get_post(id="post-2")).get_post.co_author.id, "user-2")

    async def test_skip_on_client_field_excluded(self) -> None:
        entry = (await self.client.queries.get_audit_entry(id="audit-2")).get_audit_entry
        self.assertEqual((entry.id, entry.action), ("audit-2", "LOGOUT"))


class EnumsAndListsTest(RealTestCase):
    async def test_enum_deserialization(self) -> None:
        alice = (await self.client.queries.get_user(id="user-1")).get_user
        bob = (await self.client.queries.get_user(id="user-2")).get_user
        self.assertIs(alice.status, UserStatus.ACTIVE)
        self.assertIs(alice.priority, Priority.HIGH)
        self.assertIs(bob.status, UserStatus.INACTIVE)
        self.assertIsNone(bob.priority)

    async def test_enum_argument_filters_on_server(self) -> None:
        active = (await self.client.queries.list_users_by_status(status=UserStatus.ACTIVE)).list_users_by_status
        self.assertTrue(active)
        self.assertTrue(all(u.status is UserStatus.ACTIVE for u in active))
        inactive = (await self.client.queries.list_users_by_status(status=UserStatus.INACTIVE)).list_users_by_status
        self.assertTrue(inactive)
        self.assertTrue(all(u.status is UserStatus.INACTIVE for u in inactive))
        self.assertEqual((await self.client.queries.list_users_by_status(status=UserStatus.SUSPENDED)).list_users_by_status, [])

    async def test_lists(self) -> None:
        users = (await self.client.queries.list_users()).list_users
        self.assertEqual([u.id for u in users], ["user-1", "user-2"])
        self.assertEqual(users[0].name, "Alice Smith")
        self.assertEqual(users[0].address.city, "Springfield")
        self.assertEqual({u.status for u in users}, {UserStatus.ACTIVE, UserStatus.INACTIVE})

    async def test_nullable_field_in_list_items(self) -> None:
        tags = (await self.client.queries.get_tags()).get_tags
        self.assertEqual(len(tags), 2)
        self.assertEqual((tags[0].label, tags[0].color), ("dart", "#0175C2"))
        self.assertIsNone(tags[1].color)


class CycleTest(RealTestCase):
    async def test_user_posts_cycle(self) -> None:
        user = (await self.client.queries.get_user(id="user-with-posts")).get_user
        self.assertEqual(len(user.posts), 4)
        post = user.posts[0]
        self.assertEqual((post.id, post.title, post.view_count), ("post-10", "Cyclic Post", 7))
        self.assertEqual((post.author.id, post.author.name), ("user-1", "Alice Smith"))
        self.assertEqual(post.author.address.city, "Springfield")
        self.assertIsNone((await self.client.queries.get_user(id="user-1")).get_user.posts)

    async def test_post_author_cycle(self) -> None:
        post = (await self.client.queries.get_post(id="post-10")).get_post
        self.assertEqual((post.author.id, post.author.name, post.author.email), ("user-1", "Alice Smith", "alice@test.com"))
        self.assertEqual(post.author.tags, ["admin"])


class CustomQueriesTest(RealTestCase):
    async def test_fetch_user_and_post(self) -> None:
        res = await self.client.queries.fetch_user_and_post(user_id="user-1", post_id="post-1")
        self.assertEqual((res.user.id, res.user.name), ("user-1", "Alice Smith"))
        self.assertEqual((res.post.title, res.post.author.id), ("Hello World", "user-1"))

    async def test_projected_type(self) -> None:
        res = await self.client.queries.fetch_user_summary(id="user-1")
        self.assertEqual((res.get_user.id, res.get_user.name), ("user-1", "Alice Smith"))
        self.assertIs(res.get_user.status, UserStatus.ACTIVE)

    async def test_cached_pair(self) -> None:
        for _ in range(2):
            res = await self.client.queries.fetch_cached_pair(user_id="user-1", post_id="post-1")
            self.assertEqual((res.user.name, res.post.title), ("Alice Smith", "Hello World"))

    async def test_union_dispatch(self) -> None:
        res = await self.client.queries.run_search(term="test")
        self.assertEqual(len(res.search), 2)
        self.assertIsInstance(res.search[0], UserResult)
        self.assertIsInstance(res.search[1], PostResult)
        self.assertEqual(res.search[0].name, "Alice Smith")
        self.assertEqual(res.search[1].title, "Hello World")


class LiteralArgumentsTest(RealTestCase):
    async def test_literals_against_server(self) -> None:
        found = await self.client.queries.find_first_user()
        self.assertEqual((found.find_user.name, found.find_user.email), ("Alice Smith", "alice@test.com"))
        active = await self.client.queries.list_active_users()
        self.assertEqual([u.id for u in active.list_users_by_status], ["user-1"])
        alice = await self.client.queries.search_alice()
        self.assertEqual([u.name for u in alice.search_users], ["Alice Smith"])
        limited = await self.client.queries.search_with_fixed_limit(name="s")
        self.assertEqual(len(limited.search_users), 1)
        self.assertEqual((await self.client.queries.search_price()).search_users, [])


class ErrorCaptureTest(RealTestCase):
    async def test_captured_error_response(self) -> None:
        res = await self.client.queries.get_user_or_errors(id="error-id")
        self.assertIsNotNone(res.errors)
        self.assertIsNone(res.data)
        self.assertTrue(res.errors[0].message)

    async def test_captured_success_response(self) -> None:
        res = await self.client.queries.get_user_or_errors(id="user-1")
        self.assertIsNone(res.errors)
        self.assertEqual((res.data.get_user_or_errors.name, res.data.get_user_or_errors.id), ("Alice Smith", "user-1"))

    async def test_nullable_captured_results(self) -> None:
        res = await self.client.queries.find_user_or_errors(id="error-id")
        self.assertIsNotNone(res.errors)
        self.assertIsNone(res.data.find_user_or_errors)
        res = await self.client.queries.find_user_or_errors(id="missing")
        self.assertIsNone(res.errors)
        self.assertIsNone(res.data.find_user_or_errors)

    async def test_non_captured_operation_raises(self) -> None:
        with self.assertRaises(GraphLinkException) as raised:
            await self.client.queries.get_user(id="error-id")
        self.assertTrue(raised.exception.errors[0].message)


class GlExpandTest(RealTestCase):
    async def test_car_layers(self) -> None:
        driver = (await self.client.queries.get_vehicle_driver(id="vd-1")).get_vehicle_driver
        self.assertEqual((driver.id, driver.name), ("vd-1", "Alex Driver"))
        self.assertIsInstance(driver.vehicle, Car)
        self.assertEqual(driver.vehicle.model, "Tesla Model 3")
        self.assertEqual((driver.vehicle.owner.id, driver.vehicle.owner.name), ("vo-1", "Alice Owner"))
        self.assertEqual((driver.vehicle.owner.driver.id, driver.vehicle.owner.driver.name), ("vd-1", "Alex Driver"))
        self.assertIsNone(driver.vehicle.owner.driver.vehicle)

    async def test_bike_layers(self) -> None:
        driver = (await self.client.queries.get_vehicle_driver(id="vd-2")).get_vehicle_driver
        self.assertIsInstance(driver.vehicle, Bike)
        self.assertEqual(driver.vehicle.brand, "Trek FX3")
        self.assertEqual((driver.vehicle.owner.id, driver.vehicle.owner.name), ("vo-2", "Bob Owner"))
        self.assertIsNone(driver.vehicle.owner.driver.vehicle)


if __name__ == "__main__":
    unittest.main()
