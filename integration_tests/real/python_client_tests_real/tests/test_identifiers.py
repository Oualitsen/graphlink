import unittest

from generated import Literal_, OddInput, ReservedInput

from .real_server import new_client

PY_NAMES = {
    "type": "type", "default": "default", "in": "in_", "is": "is_", "var": "var", "val": "val", "fun": "fun",
    "new": "new", "import": "import_", "return": "return_", "object": "object", "from": "from_",
    "None": "none", "True": "true", "func": "func", "range": "range", "self": "self_", "Self": "self2",
    "init": "init", "Type": "type2", "Protocol": "protocol", "async": "async_", "await": "await_",
    "package": "package", "interface": "interface", "enum": "enum", "null": "null",
}
VALUES = {wire: f"v:{wire}" for wire in PY_NAMES}
KWARGS = {py: VALUES[wire] for wire, py in PY_NAMES.items()}


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    def assert_echoed(self, reserved) -> None:
        for wire, py in PY_NAMES.items():
            self.assertEqual(getattr(reserved, py), VALUES[wire], wire)


class ReservedWords(RealTestCase):
    async def test_as_argument_names(self) -> None:
        self.assert_echoed((await self.client.queries.reserved_echo(**KWARGS)).reserved_echo)

    async def test_as_input_fields_and_response_fields(self) -> None:
        r = (await self.client.queries.reserved_echo_input(input=ReservedInput(**KWARGS))).reserved_echo_input
        self.assert_echoed(r)

    async def test_as_operation_names(self) -> None:
        q = self.client.queries
        self.assertEqual((await q.import_(value="a")).import_, "a")
        self.assertEqual((await q.default(value="b")).default, "b")
        self.assertEqual((await q.new(value="c")).new, "c")
        self.assertEqual((await q.func(value="d")).func, "d")
        self.assertEqual((await q.none(value="e")).none, "e")
        self.assertEqual((await q.self_(value="f")).self_, "f")


class LiteralLookingEnumValues(RealTestCase):
    async def test_every_value_decodes(self) -> None:
        self.assertEqual(
            (await self.client.queries.literals()).literals,
            [Literal_.DEFAULT, Literal_.CLASS, Literal_.NONE, Literal_.TRUE, Literal_.NIL,
             Literal_.UNDEFINED, Literal_.NA_N, Literal_.SELF],
        )

    async def test_every_value_round_trips_as_an_argument(self) -> None:
        values = [v for v in Literal_ if v is not Literal_.unknownValue__]
        for v in values:
            self.assertIs((await self.client.queries.literal_echo(v=v, all=values)).literal_echo, v)


class StdlibClashingTypeNames(RealTestCase):
    async def test_all_decode(self) -> None:
        c = (await self.client.queries.clashes()).clashes
        for name in ["error", "response", "request", "list", "map", "object", "optional", "date", "result", "void"]:
            self.assertEqual(getattr(c, name).id, f"{name}-1", name)


class OddNames(RealTestCase):
    async def test_every_field_round_trips(self) -> None:
        r = (await self.client.queries.odd_echo(input=OddInput(
            user_id="user_id", user_id2="userId", url_value="URLValue", http_server="HTTPServer",
            leading="_leading", trailing="trailing_", v2_name="v2_name", is_active="isActive",
            active="active", get_x="getX", x="x",
        ))).odd_echo
        self.assertEqual(
            [r.user_id, r.user_id2, r.url_value, r.http_server, r.leading, r.trailing, r.v2_name, r.is_active, r.active, r.get_x, r.x],
            ["user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_", "v2_name", "isActive", "active", "getX", "x"],
        )
