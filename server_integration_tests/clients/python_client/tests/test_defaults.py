import unittest

from generated import ConfigInput, Priority

from .fixtures import new_client


class DefaultsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_input_field_defaults_applied_when_omitted(self) -> None:
        c = (await self.client.queries.resolve_config(input=ConfigInput())).resolve_config
        self.assertEqual((c.page_size, c.ratio, c.sort, c.verbose), (25, 1.5, "asc", False))
        self.assertIs(c.priority, Priority.MEDIUM)
        self.assertEqual(c.tags, ["default", "seed"])
        self.assertEqual(c.empties, [])
        self.assertIsNone(c.note)

    async def test_explicit_values_override_defaults(self) -> None:
        c = (await self.client.queries.resolve_config(
            input=ConfigInput(page_size=5, sort="desc", priority=Priority.HIGH, note="x")
        )).resolve_config
        self.assertEqual((c.page_size, c.sort, c.note), (5, "desc", "x"))
        self.assertIs(c.priority, Priority.HIGH)

    async def test_nested_object_arg_default_merges_with_field_defaults(self) -> None:
        r = (await self.client.queries.resolve_range()).resolve_range
        self.assertEqual((r.min, r.max), (5, 100))

    async def test_argument_level_scalar_defaults(self) -> None:
        self.assertEqual((await self.client.queries.greet()).greet, "Hi world!")
        self.assertEqual((await self.client.queries.greet(name="Bob", times=2)).greet, "Hi Bob!Hi Bob!")

    async def test_enum_argument_round_trips_and_omitted_uses_default_high(self) -> None:
        self.assertIs((await self.client.queries.echo_priority(level=Priority.LOW)).echo_priority, Priority.LOW)
        self.assertIs((await self.client.queries.echo_priority()).echo_priority, Priority.HIGH)
