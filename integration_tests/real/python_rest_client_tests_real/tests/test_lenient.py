from generated import CatRest, DogRest, InMemoryGraphLinkCacheStore, OwnerRest, ProductRest

from .support import RestTestCase


class LenientCopies(RestTestCase):
    async def test_null_and_missing_fields_of_non_null_schema_fields_decode_as_none(self) -> None:
        product = await self.client.queries.lenient_product()
        self.assertEqual(product.id, "p1")
        self.assertIsNone(product.name)
        self.assertIsNone(product.price)
        self.assertIsNone(product.tags)

    async def test_nested_objects_are_lenient_too(self) -> None:
        related = (await self.client.queries.lenient_product()).related
        self.assertEqual(len(related), 2)
        self.assertEqual(related[0].id, "p2")
        self.assertIsNone(related[0].name)
        self.assertIsNone(related[0].related)
        self.assertEqual(related[1].name, "Three")
        self.assertEqual(related[1].price, 3.5)
        self.assertIsNone(related[1].related)

    async def test_lists_of_objects_decode(self) -> None:
        products = await self.client.queries.lenient_products()
        self.assertEqual(len(products), 2)
        self.assertIsNone(products[0].name)
        self.assertEqual(products[1].name, "B")

    async def test_an_empty_body_is_still_none_because_the_schema_says_so(self) -> None:
        self.assertIsNone(await self.client.queries.lenient_nothing())

    async def test_the_same_type_without_the_directive_still_fails_on_the_same_payload(self) -> None:
        with self.assertRaises(Exception) as caught:
            await self.client.queries.strict_product()
        self.assertIn("Product", str(caught.exception))
        self.assertIn("name", str(caught.exception))

    async def test_interfaces_decode_through_their_discriminator_with_missing_fields(self) -> None:
        pets = await self.client.queries.lenient_pets()
        self.assertEqual(len(pets), 3)

        first = pets[0]
        self.assertIsInstance(first, DogRest)
        self.assertEqual(first.id, "d1")
        self.assertIsNone(first.name)
        self.assertIsNone(first.barks)

        second = pets[1]
        self.assertIsInstance(second, CatRest)
        self.assertEqual(second.id, "c1")
        self.assertIsNone(second.name)
        self.assertIsNone(second.lives)

        third = pets[2]
        self.assertIsInstance(third, DogRest)
        self.assertIsNone(third.id)
        self.assertEqual(third.name, "Rex")
        self.assertIs(third.barks, True)

    async def test_the_interface_without_the_directive_still_fails_on_the_same_payload(self) -> None:
        with self.assertRaises(Exception):
            await self.client.queries.strict_pets()

    async def test_unions_decode_through_their_discriminator(self) -> None:
        hits = await self.client.queries.lenient_hits()
        self.assertIsInstance(hits[0], ProductRest)
        self.assertEqual(hits[0].id, "p1")
        self.assertIsInstance(hits[1], OwnerRest)
        self.assertEqual(hits[1].id, "o1")
        self.assertIsNone(hits[1].name)

    async def test_a_cached_lenient_result_is_stored_and_decoded_the_same_way(self) -> None:
        cached = self.new_client(store=InMemoryGraphLinkCacheStore())
        first = await cached.queries.lenient_cached()
        second = await cached.queries.lenient_cached()
        self.assertIsNone(first.name)
        self.assertIsNone(second.name)
        self.assertEqual(len(second.related), len(first.related))
        self.assertEqual(second.related[1].name, "Three")
