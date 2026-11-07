import unittest

from generated import EverythingInput, Mood, Ping, Pet, Pong, Spelling, Tree

from .real_server import new_client

NASTY = {
    "dollar": "cost $5 and ${x} and $$",
    "quote": "say \"hi\" it's",
    "backslash": "C:\\dir\\file\\n",
    "newline": "line1\nline2\ttab",
    "percent": "100% {braces} {{x}} %s %d",
    "comments": "a */ b // c /* d",
    "triple": "\"\"\" ''' ```",
    "unicode": "café 中 😀",
    "non_ascii": "é中😀",
}


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    def assert_nasty(self, echo) -> None:
        for name, expected in NASTY.items():
            self.assertEqual(getattr(echo, name), expected, name)


class StringDefaultsWithSpecialCharacters(RealTestCase):
    async def test_on_operation_arguments(self) -> None:
        self.assert_nasty((await self.client.queries.echo_nasty_args()).echo_nasty_args)

    async def test_on_input_fields_through_an_input_argument_defaulting_to_empty_object(self) -> None:
        self.assert_nasty((await self.client.queries.echo_nasty()).echo_nasty)

    async def test_an_explicit_value_replaces_the_default(self) -> None:
        r = (await self.client.queries.echo_nasty_args(dollar="$y")).echo_nasty_args
        self.assertEqual(r.dollar, "$y")
        self.assertEqual(r.quote, NASTY["quote"])


class InlineLiterals(RealTestCase):
    async def test_string_literals_written_inline_in_an_operation(self) -> None:
        r = (await self.client.queries.nasty_literal()).echo_nasty_args
        self.assertEqual(r.dollar, "cost $5 ${x}")
        self.assertEqual(r.quote, 'say "hi"')
        self.assertEqual(r.backslash, "C:\\dir")
        self.assertEqual(r.newline, "a\nb")
        self.assertEqual(r.unicode, "é😀")
        self.assertEqual(r.triple, 'block "x" ')


class DefaultsOfEveryKind(RealTestCase):
    async def test_scalars_enum_lists_nested_input_null(self) -> None:
        r = (await self.client.queries.echo_everything(input=EverythingInput())).echo_everything
        self.assertEqual((r.i, r.neg, r.big, r.f, r.exp, r.b, r.bf, r.s, r.id), (42, -7, 2147483647, 3.14, 1000.0, True, False, "x", "abc"))
        self.assertIs(r.e, Spelling.X_Y)
        self.assertEqual(r.ints, [1, 2, 3])
        self.assertEqual(r.nested, [[1], [2, 3]])
        self.assertEqual((r.inner.n, r.inner.label), (5, "inner"))
        self.assertIsNone(r.nothing)
        self.assertEqual(r.empty_list, [])
        self.assertEqual((r.empty_obj.n, r.empty_obj.label), (1, "dflt"))

    async def test_an_argument_whose_input_type_has_its_own_defaults(self) -> None:
        r = (await self.client.queries.echo_inner()).echo_inner
        self.assertEqual((r.n, r.label, r.tags), (9, "dflt", ["a"]))


class RecursiveInputs(RealTestCase):
    async def test_a_tree(self) -> None:
        tree = Tree(value=1, children=[Tree(value=2, children=[Tree(value=4)]), Tree(value=3)])
        r = (await self.client.queries.tree_stats(tree=tree)).tree_stats
        self.assertEqual(r.flat, [1, 2, 4, 3])
        self.assertEqual(r.depth, 3)

    async def test_mutually_recursive_inputs(self) -> None:
        ping = Ping(n=1, pong=Pong(n=2, ping=Ping(n=3)))
        self.assertEqual((await self.client.queries.ping_length(ping=ping)).ping_length, 3)


class OneOfInput(RealTestCase):
    async def test_the_first_member(self) -> None:
        self.assertEqual((await self.client.queries.describe_pet(pet=Pet(cat="Tom"))).describe_pet, "cat:Tom")

    async def test_the_second_member(self) -> None:
        self.assertEqual((await self.client.queries.describe_pet(pet=Pet(dog=3))).describe_pet, "dog:3")


class Deprecated(RealTestCase):
    async def test_deprecated_fields_arguments_and_enum_values_still_work(self) -> None:
        r = (await self.client.queries.legacy(with_reason="a", plain="b")).legacy
        self.assertEqual((r.old, r.older), ("a", "b"))
        self.assertIs(r.mood, Mood.CALM)
