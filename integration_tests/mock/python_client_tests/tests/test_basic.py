import json
import unittest

from generated import GraphLinkClient, Priority, UserResult, PostResult, UserStatus

from . import fixtures as fx
from .mock_adapter import MockAdapter, MockWebSocketAdapter


class BaseTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.client = GraphLinkClient(adapter=self.adapter.call, ws_adapter=MockWebSocketAdapter())

    def sent_query(self) -> str:
        return json.loads(self.adapter.last_call.raw_payload)["query"]


class ScalarsTest(BaseTest):
    async def test_non_nullable_scalars(self) -> None:
        self.adapter.register_data("getAllScalars", {"getAllScalars": fx.ALL_SCALARS_NULL})
        res = (await self.client.queries.get_all_scalars(id="scalar-1")).get_all_scalars
        self.assertEqual(res.id, "scalar-1")
        self.assertEqual(res.str_val, "hello world")
        self.assertEqual(res.int_val, 42)
        self.assertEqual(res.float_val, 3.14)
        self.assertIs(res.bool_val, True)

    async def test_nullable_scalars_null(self) -> None:
        self.adapter.register_data("getAllScalars", {"getAllScalars": fx.ALL_SCALARS_NULL})
        res = (await self.client.queries.get_all_scalars(id="scalar-1")).get_all_scalars
        for name in ("nullable_str", "nullable_int", "nullable_float", "nullable_bool", "nullable_id"):
            self.assertIsNone(getattr(res, name), name)

    async def test_nullable_scalars_present(self) -> None:
        self.adapter.register_data("getAllScalars", {"getAllScalars": fx.ALL_SCALARS_PRESENT})
        res = (await self.client.queries.get_all_scalars(id="scalar-2")).get_all_scalars
        self.assertEqual(res.nullable_str, "present")
        self.assertEqual(res.nullable_int, 99)
        self.assertEqual(res.nullable_float, 2.718)
        self.assertIs(res.nullable_bool, False)
        self.assertEqual(res.nullable_id, "nid-1")
        self.assertEqual(res.int_val, -1)
        self.assertEqual(res.float_val, -0.5)
        self.assertIs(res.bool_val, False)

    async def test_request_shape(self) -> None:
        self.adapter.register_data("getAllScalars", {"getAllScalars": fx.ALL_SCALARS_NULL})
        await self.client.queries.get_all_scalars(id="scalar-1")
        self.assertEqual(self.adapter.last_call.variables["id"], "scalar-1")
        self.assertEqual(self.adapter.last_call.operation_name, "getAllScalars")


class NullabilityTest(BaseTest):
    async def test_non_nullable_query_return(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        user = (await self.client.queries.get_user(id="user-1")).get_user
        self.assertEqual(user.id, "user-1")

    async def test_nullable_query_return(self) -> None:
        self.adapter.register_data("findUser", {"findUser": None})
        self.assertIsNone((await self.client.queries.find_user(id="x")).find_user)
        self.adapter.register_data("findUser", {"findUser": fx.USER_ALICE})
        self.assertEqual((await self.client.queries.find_user(id="user-1")).find_user.name, "Alice Smith")

    async def test_nullable_nested_object_fields(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        self.assertIsNone((await self.client.queries.get_user(id="user-1")).get_user.billing_address)
        self.adapter.register_data("getUser", {"getUser": fx.USER_BOB})
        self.assertEqual(
            (await self.client.queries.get_user(id="user-2")).get_user.billing_address.city, "Capital City"
        )

    async def test_nullable_scalar_on_nested_type(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_BOB})
        self.assertIsNone((await self.client.queries.get_user(id="user-2")).get_user.address.zip)
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        self.assertEqual((await self.client.queries.get_user(id="user-1")).get_user.address.zip, "12345")

    async def test_nullable_list_fields(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_BOB})
        self.assertIsNone((await self.client.queries.get_user(id="user-2")).get_user.scores)
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        self.assertEqual((await self.client.queries.get_user(id="user-1")).get_user.scores, [10, 20, 30])

    async def test_post_co_author(self) -> None:
        self.adapter.register_data("getPost", {"getPost": fx.POST})
        self.assertIsNone((await self.client.queries.get_post(id="post-1")).get_post.co_author)
        self.adapter.register_data("getPost", {"getPost": fx.POST_WITH_CO_AUTHOR})
        self.assertEqual((await self.client.queries.get_post(id="post-2")).get_post.co_author.name, "Bob Jones")


class NestedTypesTest(BaseTest):
    async def test_required_nested_object(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        address = (await self.client.queries.get_user(id="user-1")).get_user.address
        self.assertEqual((address.street, address.city, address.country), ("123 Main St", "Springfield", "US"))

    async def test_multi_level_nesting(self) -> None:
        self.adapter.register_data("getPost", {"getPost": fx.POST})
        post = (await self.client.queries.get_post(id="post-1")).get_post
        self.assertEqual(post.title, "Hello World")
        self.assertEqual(post.view_count, 128)
        self.assertEqual(post.author.name, "Alice Smith")
        self.assertEqual(post.author.address.city, "Springfield")

    async def test_skip_on_client_field_is_ignored(self) -> None:
        self.adapter.register_data("getAuditEntry", {"getAuditEntry": fx.AUDIT_ENTRY_WITH_EXTRA})
        entry = (await self.client.queries.get_audit_entry(id="audit-2")).get_audit_entry
        self.assertEqual(entry.action, "LOGOUT")
        self.assertFalse(hasattr(entry, "internal_note"))


class ListsTest(BaseTest):
    async def test_list_of_objects(self) -> None:
        self.adapter.register_data("listUsers", {"listUsers": [fx.USER_ALICE, fx.USER_BOB]})
        users = (await self.client.queries.list_users()).list_users
        self.assertEqual([u.id for u in users], ["user-1", "user-2"])

    async def test_empty_list_is_not_null(self) -> None:
        self.adapter.register_data("listUsers", {"listUsers": []})
        self.assertEqual((await self.client.queries.list_users()).list_users, [])

    async def test_scalar_lists(self) -> None:
        self.adapter.register_data("listUsers", {"listUsers": [fx.USER_ALICE, fx.USER_BOB]})
        alice, bob = (await self.client.queries.list_users()).list_users
        self.assertEqual(alice.tags, ["admin", "beta"])
        self.assertEqual(bob.tags, [])
        self.assertIsNone(bob.scores)

    async def test_nullable_field_in_list_items(self) -> None:
        self.adapter.register_data("getTags", {"getTags": fx.TAGS})
        tags = (await self.client.queries.get_tags()).get_tags
        self.assertEqual(tags[0].color, "#0175C2")
        self.assertIsNone(tags[1].color)

    async def test_enum_argument_sent_as_string(self) -> None:
        self.adapter.register_data("listUsersByStatus", {"listUsersByStatus": [fx.USER_ALICE]})
        await self.client.queries.list_users_by_status(status=UserStatus.ACTIVE)
        self.assertEqual(self.adapter.last_call.variables["status"], "ACTIVE")


class EnumsTest(BaseTest):
    async def test_enum_deserialization(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        user = (await self.client.queries.get_user(id="user-1")).get_user
        self.assertIs(user.status, UserStatus.ACTIVE)
        self.assertIs(user.priority, Priority.HIGH)

    async def test_nullable_enum_null(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_BOB})
        user = (await self.client.queries.get_user(id="user-2")).get_user
        self.assertIs(user.status, UserStatus.INACTIVE)
        self.assertIsNone(user.priority)

    async def test_unknown_value_falls_back(self) -> None:
        self.adapter.register_data("getUser", {"getUser": {**fx.USER_ALICE, "status": "BRAND_NEW"}})
        user = (await self.client.queries.get_user(id="user-1")).get_user
        self.assertIs(user.status, UserStatus.unknownValue__)

    async def test_fallback_is_never_serialized(self) -> None:
        with self.assertRaises(ValueError):
            UserStatus.unknownValue__.to_json()

    async def test_enum_serialization_in_variables(self) -> None:
        self.adapter.register_data("listUsersByStatus", {"listUsersByStatus": []})
        for status in (UserStatus.ACTIVE, UserStatus.INACTIVE, UserStatus.SUSPENDED):
            await self.client.queries.list_users_by_status(status=status)
            self.assertEqual(self.adapter.last_call.variables["status"], status.value)


class CycleTest(BaseTest):
    async def test_user_posts_cycle(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_WITH_POSTS})
        user = (await self.client.queries.get_user(id="user-1")).get_user
        self.assertEqual(len(user.posts), 1)
        self.assertEqual(user.posts[0].title, "Cyclic Post")
        self.assertEqual(user.posts[0].author.address.city, "Springfield")
        self.assertIsNone(user.posts[0].author.posts)

    async def test_user_posts_null(self) -> None:
        self.adapter.register_data("getUser", {"getUser": fx.USER_ALICE})
        self.assertIsNone((await self.client.queries.get_user(id="user-1")).get_user.posts)

    async def test_list_of_users_with_posts(self) -> None:
        self.adapter.register_data("listUsers", {"listUsers": [fx.USER_WITH_POSTS]})
        users = (await self.client.queries.list_users()).list_users
        self.assertEqual(users[0].posts[0].id, "post-10")


class LiteralArgumentsTest(BaseTest):
    async def test_string_literal_inline(self) -> None:
        self.adapter.register_data("findFirstUser", {"findUser": fx.USER_ALICE})
        res = await self.client.queries.find_first_user()
        self.assertEqual(res.find_user.name, "Alice Smith")
        self.assertEqual(self.adapter.last_call.variables, {})
        self.assertIn('findUser(id: "user-1")', self.sent_query())

    async def test_enum_literal_inline(self) -> None:
        self.adapter.register_data("listActiveUsers", {"listUsersByStatus": [fx.USER_ALICE]})
        res = await self.client.queries.list_active_users()
        self.assertEqual(len(res.list_users_by_status), 1)
        self.assertIn("listUsersByStatus(status: ACTIVE)", self.sent_query())

    async def test_several_literals(self) -> None:
        self.adapter.register_data("searchAlice", {"searchUsers": [fx.USER_ALICE]})
        await self.client.queries.search_alice()
        self.assertIn('searchUsers(name: "Alice",limit: 5)', self.sent_query())

    async def test_literal_and_variable_mixed(self) -> None:
        self.adapter.register_data("searchWithFixedLimit", {"searchUsers": [fx.USER_BOB]})
        await self.client.queries.search_with_fixed_limit(name="Bob")
        self.assertEqual(self.adapter.last_call.variables, {"name": "Bob"})
        self.assertIn("searchUsers(name: $name,limit: 10)", self.sent_query())

    async def test_dollar_signs_in_literal(self) -> None:
        self.adapter.register_data("searchPrice", {"searchUsers": []})
        await self.client.queries.search_price()
        self.assertIn('name: "cost $5 or $6"', self.sent_query())


class CustomQueriesTest(BaseTest):
    async def test_fetch_user_and_post(self) -> None:
        self.adapter.register_data("fetchUserAndPost", {"user": fx.USER_ALICE, "post": fx.POST})
        res = await self.client.queries.fetch_user_and_post(user_id="user-1", post_id="post-1")
        self.assertEqual(res.user.name, "Alice Smith")
        self.assertEqual(res.post.title, "Hello World")
        self.assertEqual(res.post.author.id, "user-1")

    async def test_projected_type(self) -> None:
        self.adapter.register_data(
            "fetchUserSummary", {"getUser": {"id": "user-1", "name": "Alice Smith", "status": "ACTIVE"}}
        )
        res = await self.client.queries.fetch_user_summary(id="user-1")
        self.assertEqual((res.get_user.id, res.get_user.name), ("user-1", "Alice Smith"))
        self.assertIs(res.get_user.status, UserStatus.ACTIVE)

    async def test_independent_caching(self) -> None:
        self.adapter.register_data("fetchCachedPair", {"user": fx.USER_ALICE, "post": fx.POST})
        await self.client.queries.fetch_cached_pair(user_id="user-1", post_id="post-1")
        res = await self.client.queries.fetch_cached_pair(user_id="user-1", post_id="post-1")
        self.assertEqual(self.adapter.call_count, 1)
        self.assertEqual(res.user.name, "Alice Smith")
        await self.client.queries.fetch_cached_pair(user_id="user-1", post_id="post-2")
        self.assertEqual(self.adapter.call_count, 2)

    async def test_union_dispatch(self) -> None:
        payload = {
            "search": [
                {"__typename": "UserResult", "id": "ur-1", "name": "Alice", "email": "alice@test.com"},
                {"__typename": "PostResult", "id": "pr-1", "title": "Hello World"},
            ]
        }
        for operation, call in (("search", self.client.queries.search), ("runSearch", self.client.queries.run_search)):
            self.adapter.register_data(operation, payload)
            res = await call(term="test")
            self.assertEqual(len(res.search), 2)
            self.assertIsInstance(res.search[0], UserResult)
            self.assertIsInstance(res.search[1], PostResult)
            self.assertEqual((res.search[0].id, res.search[0].name, res.search[0].email), ("ur-1", "Alice", "alice@test.com"))
            self.assertEqual((res.search[1].id, res.search[1].title), ("pr-1", "Hello World"))

    async def test_unknown_typename_raises(self) -> None:
        self.adapter.register_data("search", {"search": [{"__typename": "UnknownType", "id": "x-1"}]})
        with self.assertRaises(ValueError):
            await self.client.queries.search(term="test")


if __name__ == "__main__":
    unittest.main()
