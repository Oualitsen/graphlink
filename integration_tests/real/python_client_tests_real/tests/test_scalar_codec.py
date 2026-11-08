import json
import unittest

from generated import DefaultGraphLinkWebSocketAdapter, GraphLinkClient, ScalarsInput

from .real_server import new_client, ws_url, DEFAULT_PORT


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()


class ScalarWithACodec(RealTestCase):
    async def test_is_decoded_in_a_response(self) -> None:
        bag = (await self.client.queries.scalar_fixture()).scalar_fixture
        self.assertEqual(bag.opaque, "opaque:o-1")

    async def test_is_encoded_in_an_input_field_and_decoded_again(self) -> None:
        bag = (await self.client.queries.echo_scalars(
            input=ScalarsInput(dt="x", long=1, dts=[], opaque="opaque:xyz"))).echo_scalars
        self.assertEqual(bag.opaque, "opaque:xyz")

    async def test_is_encoded_in_an_operation_argument_and_decoded_again(self) -> None:
        bag = (await self.client.queries.echo_scalar_args(dt="x", dts=[], opaque="opaque:abc")).echo_scalar_args
        self.assertEqual(bag.opaque, "opaque:abc")

    async def test_null_stays_null_in_both_directions(self) -> None:
        self.assertIsNone((await self.client.queries.echo_scalar_args(dt="x", dts=[])).echo_scalar_args.opaque)
        bag = (await self.client.queries.echo_scalars(input=ScalarsInput(dt="x", long=1, dts=[]))).echo_scalars
        self.assertIsNone(bag.opaque)


def fixture_client(opaque: object) -> GraphLinkClient:
    response = json.dumps({"data": {"scalarFixture": {"dt": "x", "long": 1, "dts": [], "opaque": opaque}}})

    async def adapter(payload: str) -> str:
        return response

    return GraphLinkClient(adapter=adapter, ws_adapter=DefaultGraphLinkWebSocketAdapter(url=ws_url(DEFAULT_PORT)))


class ScalarWithACodecAndAJsonType(unittest.IsolatedAsyncioTestCase):
    async def test_a_value_of_the_wrong_type_fails_naming_the_field(self) -> None:
        for wire in (7, True, 1.5, {"a": 1}, ["a"]):
            with self.subTest(wire=wire):
                with self.assertRaisesRegex(TypeError, "opaque"):
                    await fixture_client(wire).queries.scalar_fixture()

    async def test_the_template_runs_on_the_right_type(self) -> None:
        bag = (await fixture_client("abc").queries.scalar_fixture()).scalar_fixture
        self.assertEqual(bag.opaque, "opaque:abc")


class PlainAliasScalars(RealTestCase):
    async def test_a_long_beyond_2_53_survives(self) -> None:
        bag = (await self.client.queries.scalar_fixture()).scalar_fixture
        self.assertEqual(bag.long, 9007199254740993)
        self.assertEqual(bag.longs, [1, None, 9223372036854775807])

    async def test_a_json_scalar_keeps_its_shape(self) -> None:
        bag = (await self.client.queries.scalar_fixture()).scalar_fixture
        self.assertEqual(bag.json_, {"name": "x", "n": 1, "list": [1, "two", False]})

    async def test_a_string_like_scalar_is_passed_through(self) -> None:
        bag = (await self.client.queries.scalar_fixture()).scalar_fixture
        self.assertEqual(bag.dt, "2026-01-02T03:04:05Z")
        self.assertEqual(bag.dts, ["2026-01-02T03:04:05Z", "2027-02-03T04:05:06Z"])

    async def test_the_long_default_reaches_the_server(self) -> None:
        bag = (await self.client.queries.echo_scalar_args(dt="x", dts=[])).echo_scalar_args
        self.assertEqual(bag.long, 9007199254740993)
