import unittest

from generated import Keyword, ReservedInput

from .fixtures import new_client


class KeywordsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_reserved_word_fields_round_trip(self) -> None:
        r = (await self.client.queries.reserved()).reserved
        self.assertEqual((r.class_, r.return_, r.new, r.default), ("cls", 42, True, "def"))
        self.assertEqual((r.is_, r.in_, r.with_, r.int, r.synchronized, r.native), ("yes", "inside", "w", 7, False, "n"))
        self.assertIs(r.kind, Keyword.CLASS)
        self.assertEqual(r.nested.value, "v")
        self.assertEqual(r.secret.token, "tok")

    async def test_reserved_operation_name_plus_reserved_argument_names(self) -> None:
        res = await self.client.queries.switch(class_="x", return_=5)
        self.assertEqual((res.switch.class_, res.switch.return_), ("x", 5))

    async def test_leading_underscore_operation(self) -> None:
        self.assertEqual((await self.client.queries.status()).status, "ok")

    async def test_colliding_field_names_stay_distinct(self) -> None:
        c = (await self.client.queries.collide()).collide
        self.assertEqual({c.class_2, c.class2}, {"A", "B"})

    async def test_reserved_word_input_fields_mutation(self) -> None:
        res = await self.client.mutations.echo_reserved(
            input=ReservedInput(class_="X", return_=5, default="D", is_=True, synchronized=3)
        )
        self.assertEqual((res.echo_reserved.class_, res.echo_reserved.return_, res.echo_reserved.default), ("X", 5, "D"))
