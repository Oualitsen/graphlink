import unittest

from generated import (
    AddressInput,
    CreateUserInput,
    GraphLinkClient,
    GraphLinkException,
    Priority,
    UpdateUserInput,
    UserStatus,
)

from . import fixtures as fx
from .mock_adapter import MockAdapter, MockWebSocketAdapter

ADDRESS_INPUT = AddressInput(street="123 Main St", city="Springfield", country="US")
MINIMAL_INPUT = CreateUserInput(name="Alice Smith", email="alice@test.com", status=UserStatus.ACTIVE, address=ADDRESS_INPUT)


class MutationTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.client = GraphLinkClient(adapter=self.adapter.call, ws_adapter=MockWebSocketAdapter())

    def sent_input(self):
        return self.adapter.last_call.variables["input"]

    async def test_create_user_deserialization(self) -> None:
        self.adapter.register_data("createUser", {"createUser": fx.USER_ALICE})
        user = (await self.client.mutations.create_user(input=MINIMAL_INPUT)).create_user
        self.assertEqual((user.id, user.name, user.email), ("user-1", "Alice Smith", "alice@test.com"))
        self.assertIs(user.status, UserStatus.ACTIVE)
        self.assertIs(user.priority, Priority.HIGH)
        self.assertEqual(user.address.street, "123 Main St")
        self.assertIsNone(user.billing_address)
        self.assertEqual(user.tags, ["admin", "beta"])
        self.assertEqual(user.scores, [10, 20, 30])

    async def test_create_user_nullable_fields_populated(self) -> None:
        self.adapter.register_data("createUser", {"createUser": fx.USER_BOB})
        user = (await self.client.mutations.create_user(input=MINIMAL_INPUT)).create_user
        self.assertIs(user.status, UserStatus.INACTIVE)
        self.assertIsNone(user.priority)
        self.assertEqual(user.billing_address.city, "Capital City")
        self.assertEqual(user.tags, [])
        self.assertIsNone(user.scores)

    async def test_create_user_request_shape(self) -> None:
        self.adapter.register_data("createUser", {"createUser": fx.USER_ALICE})
        await self.client.mutations.create_user(input=MINIMAL_INPUT)
        self.assertEqual(self.adapter.last_call.operation_name, "createUser")
        self.assertIn("input", self.adapter.last_call.variables)

    async def test_delete_user_returns_bool(self) -> None:
        self.adapter.register_data("deleteUser", {"deleteUser": True})
        self.assertIs((await self.client.mutations.delete_user(id="user-1")).delete_user, True)
        self.adapter.register_data("deleteUser", {"deleteUser": False})
        self.assertIs((await self.client.mutations.delete_user(id="user-1")).delete_user, False)
        self.assertEqual(self.adapter.last_call.variables["id"], "user-1")
        self.assertEqual(self.adapter.last_call.operation_name, "deleteUser")

    async def test_update_user(self) -> None:
        self.adapter.register_data("updateUser", {"updateUser": fx.USER_ALICE})
        res = await self.client.mutations.update_user(id="user-1", input=UpdateUserInput(name="x"))
        self.assertEqual(res.update_user.id, "user-1")
        self.assertEqual(res.update_user.name, "Alice Smith")
        self.assertIs(res.update_user.status, UserStatus.ACTIVE)
        self.assertEqual(res.update_user.address.city, "Springfield")
        self.assertEqual(self.adapter.last_call.variables["id"], "user-1")
        self.assertIn("input", self.adapter.last_call.variables)
        self.assertEqual(self.adapter.last_call.operation_name, "updateUser")


class InputsTest(MutationTest):
    def setUp(self) -> None:
        super().setUp()
        self.adapter.register_data("createUser", {"createUser": fx.USER_ALICE})
        self.adapter.register_data("updateUser", {"updateUser": fx.USER_ALICE})

    async def test_required_scalars_and_enum(self) -> None:
        await self.client.mutations.create_user(input=MINIMAL_INPUT)
        self.assertEqual(self.sent_input()["name"], "Alice Smith")
        self.assertEqual(self.sent_input()["email"], "alice@test.com")
        self.assertEqual(self.sent_input()["status"], "ACTIVE")

    async def test_nested_address(self) -> None:
        await self.client.mutations.create_user(input=MINIMAL_INPUT)
        address = self.sent_input()["address"]
        self.assertEqual(address, {"street": "123 Main St", "city": "Springfield", "country": "US", "zip": None})

    async def test_optional_fields(self) -> None:
        await self.client.mutations.create_user(input=MINIMAL_INPUT)
        self.assertIsNone(self.sent_input()["priority"])
        self.assertIsNone(self.sent_input()["billingAddress"])
        provided = CreateUserInput(
            name="Alice",
            email="a@b.com",
            status=UserStatus.ACTIVE,
            priority=Priority.CRITICAL,
            address=ADDRESS_INPUT,
            tags=["admin", "beta"],
        )
        await self.client.mutations.create_user(input=provided)
        self.assertEqual(self.sent_input()["priority"], "CRITICAL")
        self.assertEqual(self.sent_input()["tags"], ["admin", "beta"])
        await self.client.mutations.create_user(input=provided.model_copy(update={"tags": []}))
        self.assertEqual(self.sent_input()["tags"], [])

    async def test_update_input_only_provided_fields(self) -> None:
        await self.client.mutations.update_user(id="user-1", input=UpdateUserInput(name="New Name"))
        sent = self.sent_input()
        self.assertEqual(sent["name"], "New Name")
        self.assertIsNone(sent["email"])
        self.assertIsNone(sent["status"])

    async def test_update_id_is_top_level_variable(self) -> None:
        await self.client.mutations.update_user(id="user-42", input=UpdateUserInput(status=UserStatus.INACTIVE))
        self.assertEqual(self.adapter.last_call.variables["id"], "user-42")
        self.assertEqual(self.sent_input()["status"], "INACTIVE")


class ErrorCaptureTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.client = GraphLinkClient(adapter=self.adapter.call, ws_adapter=MockWebSocketAdapter())

    async def test_query_error_response(self) -> None:
        for operation, call in (
            ("getUserOrErrors", self.client.queries.get_user_or_errors),
            ("findUserOrErrors", self.client.queries.find_user_or_errors),
        ):
            self.adapter.register_errors(operation, [fx.GRAPHQL_ERROR])
            res = await call(id="user-1")
            self.assertIsNotNone(res.errors)
            self.assertIsNone(res.data)
            self.assertEqual(res.errors[0].message, "Not found")

    async def test_query_success_response(self) -> None:
        self.adapter.register_data("getUserOrErrors", {"getUserOrErrors": fx.USER_ALICE})
        res = await self.client.queries.get_user_or_errors(id="user-1")
        self.assertIsNone(res.errors)
        self.assertEqual(res.data.get_user_or_errors.name, "Alice Smith")
        self.assertEqual(res.data.get_user_or_errors.id, "user-1")

    async def test_mutation_error_and_success(self) -> None:
        self.adapter.register_errors("createUserOrErrors", [fx.GRAPHQL_ERROR])
        res = await self.client.mutations.create_user_or_errors(input=MINIMAL_INPUT)
        self.assertIsNone(res.data)
        self.assertEqual(res.errors[0].message, "Not found")
        self.adapter.register_data("createUserOrErrors", {"createUserOrErrors": fx.USER_ALICE})
        res = await self.client.mutations.create_user_or_errors(input=MINIMAL_INPUT)
        self.assertIsNone(res.errors)
        self.assertEqual(res.data.create_user_or_errors.name, "Alice Smith")

    async def test_non_captured_operation_raises_with_errors(self) -> None:
        self.adapter.register_errors("getUser", [fx.GRAPHQL_ERROR])
        with self.assertRaises(GraphLinkException) as raised:
            await self.client.queries.get_user(id="user-1")
        self.assertEqual(raised.exception.errors[0].message, "Not found")


if __name__ == "__main__":
    unittest.main()
