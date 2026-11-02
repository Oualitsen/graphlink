from urllib.parse import quote

from generated import Address, Filter, Geo, Meta, Row, Status

from . import variant
from .support import RestTestCase, header, query_pairs, query_value


class ScalarsAndPaths(RestTestCase):
    async def test_every_scalar_kind_is_a_query_value(self) -> None:
        e = await self.client.queries.e_scalars(id="x1", s="hello", i=3, f=2.5, b=True, st=Status.ARCHIVED, renamed="r")
        self.assertEqual(e.method, "GET")
        self.assertEqual(e.path, "/echo/scalars/x1")
        self.assertEqual(query_pairs(e), ["s=hello", "i=3", "f=2.5", "b=true", "st=ARCHIVED", "dflt=5", "x-ren=r"])
        self.assertEqual(e.body_size, 0)
        self.assertIsNone(e.content_type)
        self.assertEqual(header(e, "accept"), "application/json")

    async def test_omitted_optional_absent_default_sent_explicit_replaces(self) -> None:
        self.assertEqual(query_pairs(await self.client.queries.e_scalars(id="x1")), ["dflt=5"])
        self.assertEqual(query_pairs(await self.client.queries.e_scalars(id="x1", dflt=9)), ["dflt=9"])

    async def test_false_and_zero_are_values_not_omissions(self) -> None:
        e = await self.client.queries.e_scalars(id="x1", b=False, i=0, s="")
        self.assertEqual(query_pairs(e), ["s=", "i=0", "b=false", "dflt=5"])

    async def test_reserved_and_non_ascii_characters_survive(self) -> None:
        segment = "a b/c?d#é+%"
        value = 'a&b=c d+e/é"%25'
        e = await self.client.queries.e_special(segment=segment, q=value, other="ü")
        self.assertEqual(e.path, f"/echo/special/{quote(segment, safe='')}/tail")
        self.assertEqual(query_value(e, "q"), value)
        self.assertEqual(query_value(e, "other"), "ü")

    async def test_empty_string_is_not_dropped(self) -> None:
        e = await self.client.queries.e_special(segment="seg", q="")
        self.assertEqual(query_value(e, "q"), "")

    async def test_delete_carries_arguments_in_the_query(self) -> None:
        e = await self.client.queries.e_delete_query(id="d1", force=True)
        self.assertEqual((e.method, e.path, e.body_size), ("DELETE", "/echo/delete/d1", 0))
        self.assertEqual(query_pairs(e), ["force=true"])


class Lists(RestTestCase):
    async def test_scalar_lists_repeat_or_join_and_empty_sends_nothing(self) -> None:
        e = await self.client.queries.e_lists(tags=["a", "b c"], ids=[1, 2, 3], empty=[])
        self.assertEqual(query_pairs(e), [*variant.lst("tags", ["a", "b c"]), *variant.lst("ids", ["1", "2", "3"])])
        self.assertIsNone(query_value(e, "empty"))

    async def test_matrix_uses_indexed_keys(self) -> None:
        e = await self.client.queries.e_lists(matrix=[[1, 2], [3]])
        self.assertEqual(
            query_pairs(e),
            [f"{variant.key('matrix', [0, 0])}=1", f"{variant.key('matrix', [0, 1])}=2", f"{variant.key('matrix', [1, 0])}=3"],
        )

    async def test_list_of_objects_uses_indexed_keys(self) -> None:
        e = await self.client.queries.e_lists(rows=[Row(name="r0", ids=[1, 2]), Row(name="r1")])
        self.assertEqual(
            query_pairs(e),
            [
                f"{variant.key('rows', [0, 'name'])}=r0",
                *variant.lst(variant.key("rows", [0, "ids"]), ["1", "2"]),
                f"{variant.key('rows', [1, 'name'])}=r1",
            ],
        )

    async def test_items_with_reserved_characters_round_trip(self) -> None:
        e = await self.client.queries.e_lists(tags=["a&b", "c=d", "e f", "é"])
        if variant.COMMA:
            self.assertEqual(query_value(e, "tags"), "a&b,c=d,e f,é")
        else:
            self.assertEqual("|".join(p.value for p in e.query if p.name == "tags"), "a&b|c=d|e f|é")


class Objects(RestTestCase):
    async def test_input_is_spread_by_default(self) -> None:
        e = await self.client.queries.e_objects(filter=Filter(tag="x", min_price=3.0, status=Status.ACTIVE))
        self.assertEqual(query_pairs(e), ["tag=x", "minPrice=3.0", "status=ACTIVE"])

    async def test_spread_input_with_unset_fields_sends_only_set_ones(self) -> None:
        e = await self.client.queries.e_objects(filter=Filter(tag="x"))
        self.assertEqual(query_pairs(e), ["tag=x"])

    async def test_flat_nests_with_the_configured_separator(self) -> None:
        meta = Meta(name="m", tags=["t1", "t2"], address=Address(city="Oran", street="Rue 1", geo=Geo(lat=35.7, lng=-0.6)))
        e = await self.client.queries.e_objects(meta=meta)
        self.assertEqual(
            query_pairs(e),
            [
                f"{variant.key('meta', ['name'])}=m",
                *variant.lst(variant.key("meta", ["tags"]), ["t1", "t2"]),
                f"{variant.key('meta', ['address', 'city'])}=Oran",
                f"{variant.key('meta', ['address', 'street'])}=Rue 1",
                f"{variant.key('meta', ['address', 'geo', 'lat'])}=35.7",
                f"{variant.key('meta', ['address', 'geo', 'lng'])}=-0.6",
            ],
        )

    async def test_json_encoding_sends_one_key_holding_json_text(self) -> None:
        import json

        e = await self.client.queries.e_objects(as_json=Meta(name="m", tags=["a"], address=Address(city="c")))
        self.assertEqual([p.name for p in e.query], ["j"])
        decoded = json.loads(query_value(e, "j") or "")
        self.assertEqual(decoded["name"], "m")
        self.assertEqual(decoded["tags"], ["a"])
        self.assertEqual(decoded["address"]["city"], "c")

    async def test_several_roles_keep_their_own_keys(self) -> None:
        e = await self.client.queries.e_objects(filter=Filter(tag="x"), meta=Meta(name="m"), as_json=Meta(name="j"))
        self.assertEqual({p.name for p in e.query}, {"tag", variant.key("meta", ["name"]), "j"})
