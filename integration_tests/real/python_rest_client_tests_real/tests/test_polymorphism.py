from generated import Cat, Dog, Owner, Product

from .support import RestTestCase


class Nested(RestTestCase):
    async def test_interface_and_union_fields_inside_an_object(self) -> None:
        kennel = await self.client.queries.kennel()
        self.assertIsInstance(kennel.resident, Dog)
        self.assertTrue(kennel.resident.barks)
        self.assertIsInstance(kennel.hit, Product)
        self.assertEqual(kennel.hit.name, "Pen")

    async def test_lists_of_interfaces_and_unions_inside_an_object(self) -> None:
        kennel = await self.client.queries.kennel()
        self.assertEqual([type(p) for p in kennel.featured], [Dog, Cat])
        self.assertEqual(kennel.featured[1].lives, 9)
        self.assertEqual([type(h) for h in kennel.hits], [Product, Owner])

    async def test_null_elements_in_a_list_of_interfaces(self) -> None:
        mixed = (await self.client.queries.kennel()).mixed
        self.assertEqual(len(mixed), 3)
        self.assertIsInstance(mixed[0], Dog)
        self.assertIsNone(mixed[1])
        self.assertIsInstance(mixed[2], Cat)

    async def test_null_polymorphic_fields(self) -> None:
        empty = (await self.client.queries.shelter()).kennels[1]
        self.assertIsNone(empty.resident)
        self.assertEqual(empty.featured, [])
        self.assertIsNone(empty.mixed)
        self.assertIsNone(empty.hit)
        self.assertIsNone(empty.hits)

    async def test_two_levels_deep(self) -> None:
        shelter = await self.client.queries.shelter()
        self.assertEqual(len(shelter.kennels), 2)
        self.assertIsInstance(shelter.kennels[0].resident, Dog)
        self.assertEqual(shelter.kennels[0].featured[1].name, "Tom")


class Results(RestTestCase):
    async def test_nullable_elements_keep_null(self) -> None:
        pets = await self.client.queries.pets_nullable()
        self.assertEqual(len(pets), 3)
        self.assertIsInstance(pets[0], Dog)
        self.assertIsNone(pets[1])
        self.assertIsInstance(pets[2], Cat)

    async def test_optional_list_decodes_a_json_null_as_null(self) -> None:
        self.assertIsNone(await self.client.queries.pets_optional())

    async def test_through_response_path(self) -> None:
        pets = await self.client.queries.pets_wrapped()
        self.assertEqual([type(p) for p in pets], [Dog, Cat])

    async def test_from_a_mutation(self) -> None:
        pet = await self.client.mutations.adopt_pet(id="c9")
        self.assertIsInstance(pet, Cat)
        self.assertEqual(pet.id, "c9")
        self.assertEqual(pet.name, "Adopted")

    async def test_from_a_cached_operation(self) -> None:
        first = await self.client.queries.cached_pet(id="d7")
        second = await self.client.queries.cached_pet(id="d7")
        self.assertIsInstance(first, Dog)
        self.assertEqual(first.name, "Rex1")
        self.assertEqual(second.name, "Rex1")
        self.assertEqual((await self.client.queries.cached_pet(id="d8")).name, "Rex1")


class PayloadProblems(RestTestCase):
    async def test_discriminator_key_absent(self) -> None:
        with self.assertRaisesRegex(Exception, r"Pet.*kind"):
            await self.client.queries.pet_no_kind()

    async def test_discriminator_null(self) -> None:
        with self.assertRaisesRegex(Exception, r"Pet.*kind"):
            await self.client.queries.pet_null_kind()

    async def test_unknown_keys_inside_a_member_are_ignored(self) -> None:
        pet = await self.client.queries.pet_extra_keys()
        self.assertIsInstance(pet, Dog)
        self.assertEqual(pet.name, "Rex")

    async def test_a_member_missing_a_required_field_names_the_field(self) -> None:
        with self.assertRaisesRegex(Exception, r"barks"):
            await self.client.queries.pet_missing_field()
