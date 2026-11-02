import json

from generated import Cat, Dog, Owner, Product, RestError, Status

from .support import RestTestCase


class StatusHandling(RestTestCase):
    async def test_200_and_201_decode_the_body(self) -> None:
        self.assertEqual((await self.client.queries.status(code=200)).name, "Pen")
        self.assertEqual((await self.client.queries.status(code=201)).id, "p1")

    async def test_204_is_null_when_nullable_and_an_error_when_not(self) -> None:
        self.assertIsNone(await self.client.queries.status(code=204))
        with self.assertRaisesRegex(ValueError, "Empty REST response"):
            await self.client.queries.status_non_null(code=204)

    async def test_error_statuses_raise_rest_error(self) -> None:
        for code in [400, 401, 403, 404, 409, 422, 500, 502, 503]:
            with self.subTest(code=code):
                with self.assertRaises(RestError) as caught:
                    await self.client.queries.status(code=code)
                error = caught.exception
                self.assertEqual(error.status, code)
                self.assertIn(f"status {code}", error.body)
                self.assertEqual(error.headers["x-reason"], f"reason-{code}")

    async def test_rest_error_prints_its_status(self) -> None:
        with self.assertRaises(RestError) as caught:
            await self.client.queries.status(code=418)
        self.assertIn("418", str(caught.exception))

    async def test_failed_call_does_not_poison_the_next_one(self) -> None:
        with self.assertRaises(RestError):
            await self.client.queries.status(code=500)
        self.assertEqual((await self.client.queries.status(code=200)).id, "p1")


class EmptyBodies(RestTestCase):
    async def test_empty_200_null_or_error(self) -> None:
        self.assertIsNone(await self.client.queries.blank())
        with self.assertRaisesRegex(ValueError, "Empty REST response"):
            await self.client.queries.blank_non_null()

    async def test_204_and_json_null_are_null_when_nullable(self) -> None:
        self.assertIsNone(await self.client.queries.no_content())
        self.assertIsNone(await self.client.queries.text_optional())
        self.assertIsNone(await self.client.queries.json_null())


class ValueKinds(RestTestCase):
    async def test_scalars_and_text(self) -> None:
        self.assertEqual(await self.client.queries.count(), 7)
        self.assertIs(await self.client.queries.flag(), True)
        self.assertEqual(await self.client.queries.text(), "héllo ✓")

    async def test_response_path_selects_a_nested_value(self) -> None:
        self.assertEqual(await self.client.queries.deep(), [1, 2, 3])
        self.assertEqual([p.id for p in await self.client.queries.wrapped()], ["p1", "p2"])

    async def test_non_ascii_json_decodes(self) -> None:
        p = await self.client.queries.unicode()
        self.assertEqual(p.name, 'é漢😀 "quoted"')
        self.assertEqual(p.tags, ["ß"])

    async def test_unknown_keys_ignored_and_null_list_stays_null(self) -> None:
        p = await self.client.queries.extra_keys()
        self.assertEqual(p.id, "x")
        self.assertIsNone(p.tags)

    async def test_missing_non_null_field_is_a_decode_error_naming_the_type_and_field(self) -> None:
        with self.assertRaises(Exception) as caught:
            await self.client.queries.missing_field()
        self.assertIn("Product", str(caught.exception))
        self.assertIn("name", str(caught.exception))

    async def test_nested_types_enums_and_cycles_decode(self) -> None:
        p = await self.client.queries.product(id="p1")
        self.assertEqual(p.status, Status.ACTIVE)
        self.assertEqual(len(p.related), 1)
        self.assertEqual(p.related[0].name, "Book")
        self.assertIsNone(p.related[0].related)


class Polymorphism(RestTestCase):
    async def test_interface_decodes_through_the_discriminator(self) -> None:
        pets = await self.client.queries.pets()
        self.assertIsInstance(pets[0], Dog)
        self.assertTrue(pets[0].barks)
        self.assertIsInstance(pets[1], Cat)
        self.assertEqual(pets[1].lives, 9)

    async def test_single_interface_value(self) -> None:
        pet = await self.client.queries.pet(id="c1")
        self.assertIsInstance(pet, Cat)
        self.assertEqual(pet.name, "Tom")

    async def test_unknown_discriminator_value_names_the_parent_and_value(self) -> None:
        with self.assertRaisesRegex(Exception, r"Pet.*bird"):
            await self.client.queries.pets_unknown()

    async def test_union_decodes_through_its_discriminator_map(self) -> None:
        hits = await self.client.queries.hits()
        self.assertIsInstance(hits[0], Product)
        self.assertIsInstance(hits[1], Owner)


class MixedClient(RestTestCase):
    async def test_graphql_and_rest_are_served_by_the_same_client(self) -> None:
        self.assertEqual((await self.client.queries.get_count()).get_count, 19)
        self.assertEqual(await self.client.queries.count(), 7)
        self.assertEqual((await self.client.queries.get_count()).get_count, 19)


class TransportEdgeCases(RestTestCase):
    async def test_gzip_is_decompressed(self) -> None:
        self.assertEqual([p.id for p in await self.client.queries.gzipped()], ["p1", "p2"])

    async def test_redirect_is_followed(self) -> None:
        self.assertEqual(await self.client.queries.redirected(), 7)

    async def test_large_json_response_decodes_completely(self) -> None:
        items = await self.client.queries.big(n=50000)
        self.assertEqual(len(items), 50000)
        self.assertEqual(items[-1].name, "big-49999")

    async def test_invalid_json_is_a_format_error_not_a_rest_error(self) -> None:
        with self.assertRaises(json.JSONDecodeError):
            await self.client.queries.invalid_json()

    async def test_non_json_error_body_is_kept_as_text(self) -> None:
        with self.assertRaises(RestError) as caught:
            await self.client.queries.html_error()
        error = caught.exception
        self.assertEqual(error.status, 500)
        self.assertIn("Internal Server Error", error.body)
        self.assertRegex(error.headers["content-type"], r"^text/html")
