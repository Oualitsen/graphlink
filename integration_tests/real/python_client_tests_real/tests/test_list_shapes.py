import unittest

from generated import ArgOnly, ListsInput, OnlyOne, Phase, Phased, RespOnly, Spelling

from .real_server import new_client

KNOWN = [v for v in Spelling if v is not Spelling.unknownValue__]


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def shapes(self, mode: str):
        return (await self.client.queries.list_shapes(mode=mode)).list_shapes


class ListShapesWithNulls(RealTestCase):
    async def test_scalars(self) -> None:
        s = await self.shapes("full")
        self.assertEqual(s.a, [1, 2, 3])
        self.assertEqual(s.b, [1, 2, 3])
        self.assertEqual(s.c, [1, None, 3])
        self.assertEqual(s.d, [None])

    async def test_nested_lists(self) -> None:
        s = await self.shapes("full")
        self.assertEqual(s.e, [[1, 2], [3]])
        self.assertEqual(s.f, [[1, None], None])

    async def test_enums(self) -> None:
        self.assertEqual((await self.shapes("full")).g, [Spelling.A, None, Spelling.B2])

    async def test_objects_unions_and_interfaces(self) -> None:
        s = await self.shapes("full")
        self.assertEqual([None if v is None else v.width for v in s.h], [640, None])
        self.assertEqual([None if v is None else type(v).__name__ for v in s.i], ["Photo", None, "Video"])
        self.assertEqual([None if v is None else type(v).__name__ for v in s.j], ["Comment", None])


class EmptyVersusNull(RealTestCase):
    async def test_empty_lists_stay_empty(self) -> None:
        s = await self.shapes("empty")
        self.assertEqual((s.b, s.d, s.f, s.e), ([], [], [], []))

    async def test_null_lists_stay_null_while_required_ones_are_empty(self) -> None:
        s = await self.shapes("null")
        self.assertIsNone(s.b)
        self.assertIsNone(s.d)
        self.assertIsNone(s.f)
        self.assertEqual((s.a, s.g, s.i), ([], [], []))


class ListArguments(RealTestCase):
    async def test_every_shape_round_trips(self) -> None:
        r = (await self.client.queries.echo_args(
            a=[1, 2], b=[1, None], c=[[1], [], [2, 3]],
            e=[Spelling.X_Y, Spelling.HTTP2_OK], f=[None, Spelling.V1],
        )).echo_args
        self.assertEqual(r.a, [1, 2])
        self.assertEqual(r.b, [1, None])
        self.assertEqual(r.c, [[1], [], [2, 3]])
        self.assertEqual(r.e, [Spelling.X_Y, Spelling.HTTP2_OK])
        self.assertEqual(r.f, [None, Spelling.V1])

    async def test_omitted_lists_are_null_and_defaults_apply(self) -> None:
        r = (await self.client.queries.echo_args(a=[], e=[])).echo_args
        self.assertIsNone(r.b)
        self.assertIsNone(r.c)
        self.assertIsNone(r.f)
        self.assertEqual(r.g, [Spelling.A, Spelling.B2])
        self.assertEqual(r.one, OnlyOne.ONLY)

    async def test_explicitly_empty_default_bearing_list_is_kept(self) -> None:
        self.assertEqual((await self.client.queries.echo_args(a=[], e=[], g=[])).echo_args.g, [])


class ListInputFields(RealTestCase):
    async def test_every_shape_round_trips(self) -> None:
        r = (await self.client.queries.echo_input(input=ListsInput(
            a=[3, 4], b=[None, 5], c=[[1, 2], []], e=[Spelling.SNAKE_CASE_2], f=[Spelling.A, None], g=[Spelling.V1],
        ))).echo_input
        self.assertEqual(r.a, [3, 4])
        self.assertEqual(r.b, [None, 5])
        self.assertEqual(r.c, [[1, 2], []])
        self.assertEqual(r.e, [Spelling.SNAKE_CASE_2])
        self.assertEqual(r.f, [Spelling.A, None])
        self.assertEqual(r.g, [Spelling.V1])

    async def test_input_defaults_reach_the_server(self) -> None:
        r = (await self.client.queries.echo_input(input=ListsInput(a=[], e=[]))).echo_input
        self.assertEqual(r.g, [Spelling.A, Spelling.B2])
        self.assertEqual(r.one, OnlyOne.ONLY)


class LargeLists(RealTestCase):
    async def test_50000_scalars(self) -> None:
        r = (await self.client.queries.big_ints(n=50000)).big_ints
        self.assertEqual(len(r), 50000)
        self.assertEqual(r[-1], 49999)

    async def test_20000_objects(self) -> None:
        r = (await self.client.queries.big_photos(n=20000)).big_photos
        self.assertEqual(len(r), 20000)
        self.assertEqual((r[-1].id, r[-1].width), ("p19999", 19999))


class EnumSpellings(RealTestCase):
    async def test_every_spelling_round_trips(self) -> None:
        r = (await self.client.queries.echo_args(a=[], e=KNOWN)).echo_args
        self.assertEqual(r.e, KNOWN)

    def test_wire_names(self) -> None:
        self.assertEqual([v.to_json() for v in KNOWN], ["A", "B2", "x__y", "http2_ok", "v1", "snake_case_2"])

    async def test_enum_used_only_as_argument(self) -> None:
        self.assertEqual((await self.client.queries.arg_only(v=ArgOnly.P2)).arg_only, "P2")

    async def test_enum_used_only_in_response(self) -> None:
        self.assertEqual((await self.client.queries.resp_only()).resp_only, RespOnly.R2)


class UnknownEnumValue(RealTestCase):
    async def test_in_a_field(self) -> None:
        p = (await self.client.queries.phase_probe()).phase_probe
        self.assertIs(p.single, Phase.unknownValue__)
        self.assertIs(p.maybe, Phase.unknownValue__)

    async def test_in_list_elements_known_ones_untouched(self) -> None:
        p = (await self.client.queries.phase_probe()).phase_probe
        self.assertEqual(p.list, [Phase.OPEN, Phase.unknownValue__, Phase.CLOSED])
        self.assertEqual(p.nullable_list, [Phase.unknownValue__, None])

    async def test_in_a_union_member(self) -> None:
        h = (await self.client.queries.phase_holder()).phase_holder
        self.assertIsInstance(h, Phased)
        self.assertIs(h.phase, Phase.unknownValue__)
