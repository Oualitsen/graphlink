import asyncio
import unittest

from generated import (
    Article,
    Basket,
    Comment,
    Document,
    InnerInput,
    Pet,
    Photo,
    Pick,
    Span,
    Stamp,
    UserStatus,
    Video,
)

from .real_server import new_client, new_ws_adapter


def names(values):
    return [None if v is None else type(v).__name__ for v in values]


class RealTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()


class NestedListsOfPolymorphicTypes(RealTestCase):
    async def test_lists_of_lists_of_unions_and_interfaces(self) -> None:
        grid = (await self.client.queries.grid()).grid
        self.assertEqual([names(row) for row in grid.cells], [["Photo", None], ["Video"], []])
        self.assertEqual([names(row) for row in grid.rows], [["Article", "Comment"], ["Article"]])
        self.assertEqual(names(grid.maybe[0]), ["Photo", "Document"])

    async def test_empty_and_null_lists_stay_as_they_are(self) -> None:
        grid = (await self.client.queries.grid(empty=True)).grid
        self.assertEqual(grid.cells, [])
        self.assertEqual(grid.rows, [])
        self.assertIsNone(grid.maybe)

    async def test_a_projected_selection_of_nested_lists(self) -> None:
        grid = (await self.client.queries.grid_projected()).grid
        self.assertEqual(grid.cells[0][0].width, 640)
        self.assertIsNone(grid.cells[0][1])
        self.assertEqual(grid.cells[1][0].seconds, 30)
        self.assertEqual(grid.cells[2], [])
        self.assertEqual([e.id for e in grid.rows[0]], ["a1", "c1"])
        self.assertEqual(grid.rows[0][0].title, "Hello")
        self.assertEqual(grid.rows[0][1].text, "Nice")
        self.assertEqual(grid.maybe[0][0].url, "http://cdn/1.png")
        self.assertEqual(grid.maybe[0][1].id, "d1")


class CustomScalarsInsidePolymorphicTypes(RealTestCase):
    async def test_a_list_of_a_union_with_scalar_fields(self) -> None:
        moments = (await self.client.queries.moments()).moments
        self.assertIsInstance(moments[0], Stamp)
        self.assertEqual(moments[0].at, "2026-01-02T03:04:05Z")
        self.assertEqual(moments[0].big, 4294967296)
        self.assertIsInstance(moments[1], Span)
        self.assertEqual(moments[1].until, "2026-02-04")
        self.assertEqual(moments[1].opaque, "opaque:o-9")
        self.assertEqual(moments[1].dts, ["2026-03-04T05:06:07Z"])

    async def test_a_list_of_an_interface_with_scalar_fields(self) -> None:
        timed = (await self.client.queries.timed()).timed
        self.assertEqual(names(timed), ["Span", "Stamp"])
        self.assertEqual(timed[0].opaque, "opaque:o-9")
        self.assertEqual(timed[1].big, 4294967296)

    async def test_a_projected_union_keeps_the_scalars_it_selects(self) -> None:
        moments = (await self.client.queries.moments_projected()).moments
        self.assertEqual(moments[0].at, "2026-01-02T03:04:05Z")
        self.assertEqual(moments[0].big, 4294967296)
        self.assertEqual(moments[1].opaque, "opaque:o-9")
        self.assertEqual(moments[1].until, "2026-02-04")

    async def test_an_interface_selection_shares_the_interface_scalar(self) -> None:
        timed = (await self.client.queries.timed_projected()).timed
        self.assertEqual([t.at for t in timed], ["2026-02-03T04:05:06Z", "2026-01-02T03:04:05Z"])
        self.assertEqual(timed[0].opaque, "opaque:o-9")
        self.assertEqual(timed[1].big, 4294967296)


class UnionMemberPointingBackAtItsUnion(RealTestCase):
    async def test_three_levels_deep(self) -> None:
        chain = (await self.client.queries.chain_deep(id="l1")).chain
        self.assertEqual(chain.id, "l1")
        self.assertEqual(chain.next.id, "l2")
        self.assertEqual(chain.next.next.id, "e1")
        self.assertEqual(chain.next.next.reason, "done")

    async def test_the_end_of_the_chain_directly_and_an_unknown_id(self) -> None:
        self.assertEqual((await self.client.queries.chain_deep(id="e1")).chain.reason, "done")
        self.assertIsNone((await self.client.queries.chain_deep(id="nope")).chain)

    async def test_the_all_fields_selection_stops_after_one_level(self) -> None:
        chain = (await self.client.queries.chain(id="l1")).chain
        self.assertEqual(chain.id, "l1")
        self.assertEqual(chain.next.id, "l2")


class ListsOfUnionsInEveryOperationKind(RealTestCase):
    async def cached_seconds(self) -> int:
        return (await self.client.queries.cached_attachments()).cached_attachments[1].seconds

    async def test_a_cached_list_is_served_once_and_fetched_again_after_its_tag_is_evicted(self) -> None:
        self.assertEqual(names((await self.client.queries.cached_attachments()).cached_attachments), ["Photo", "Video", "Document"])
        before = await self.cached_seconds()
        self.assertEqual(await self.cached_seconds(), before)
        await self.client.mutations.evict_attachments()
        self.assertNotEqual(await self.cached_seconds(), before)

    async def test_an_error_on_a_list_of_unions_throws_and_a_good_call_still_works(self) -> None:
        with self.assertRaises(Exception):
            await self.client.queries.failing_attachments(fail=True)
        self.assertEqual(len((await self.client.queries.failing_attachments(fail=False)).failing_attachments), 3)

    async def test_a_mutation_returning_a_list_of_unions(self) -> None:
        five = (await self.client.mutations.bulk_attachments(n=5)).bulk_attachments
        self.assertEqual(names(five), ["Photo", "Video", "Document", "Photo", "Video"])
        self.assertEqual((await self.client.mutations.bulk_attachments(n=0)).bulk_attachments, [])

    async def test_a_mutation_returning_a_list_of_an_interface(self) -> None:
        entities = (await self.client.mutations.bulk_entities()).bulk_entities
        self.assertEqual(names(entities), ["Article", "Comment", "Article"])


class ListSubscriptions(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.ws = new_ws_adapter()
        self.client = new_client(ws_adapter=self.ws)

    async def asyncTearDown(self) -> None:
        await self.ws.close()

    async def _take(self, stream, count):
        events = []
        try:
            while len(events) < count:
                events.append(await asyncio.wait_for(stream.__anext__(), 10))
        finally:
            await stream.aclose()
        return events

    async def test_a_subscription_emitting_lists_of_unions(self) -> None:
        batches = await self._take(self.client.subscriptions.attachments_batch(), 2)
        self.assertEqual(names(batches[0].attachments_batch), ["Photo", "Video", "Document"])
        self.assertEqual(names(batches[1].attachments_batch), ["Document"])

    async def test_a_subscription_emitting_a_list_of_an_interface(self) -> None:
        [batch] = await self._take(self.client.subscriptions.entity_batch(), 1)
        self.assertEqual(names(batch.entity_batch), ["Article", "Comment"])


class OneOfInputsWithRicherMembers(RealTestCase):
    async def pick(self, pick: Pick) -> str:
        return (await self.client.queries.describe_pick(pick=pick)).describe_pick

    async def test_an_input_object(self) -> None:
        self.assertEqual(await self.pick(Pick(inner=InnerInput(n=5, label="x", tags=["t"]))), "{inner={label=x, n=5, tags=[t]}}")

    async def test_an_enum(self) -> None:
        self.assertEqual(await self.pick(Pick(status=UserStatus.SUSPENDED)), "{status=SUSPENDED}")

    async def test_a_list_including_an_empty_one(self) -> None:
        self.assertEqual(await self.pick(Pick(ids=[1, 2])), "{ids=[1, 2]}")
        self.assertEqual(await self.pick(Pick(ids=[])), "{ids=[]}")

    async def test_another_one_of_input(self) -> None:
        self.assertEqual(await self.pick(Pick(pet=Pet(cat="Tom"))), "{pet={cat=Tom}}")

    async def test_itself_nested(self) -> None:
        self.assertEqual(await self.pick(Pick(child=Pick(child=Pick(pet=Pet(dog=3))))), "{child={child={pet={dog=3}}}}")

    async def test_a_list_of_one_of_inputs_inside_a_regular_input(self) -> None:
        pets = [Pet(cat="a"), Pet(dog=2)]
        both = await self.client.queries.describe_basket(basket=Basket(pets=pets, lead=Pet(dog=3)))
        self.assertEqual(both.describe_basket, "{lead={dog=3}, pets=[{cat=a}, {dog=2}]}")
        no_lead = await self.client.queries.describe_basket(basket=Basket(pets=pets))
        self.assertEqual(no_lead.describe_basket, "{pets=[{cat=a}, {dog=2}]}")
        empty = await self.client.queries.describe_basket(basket=Basket(pets=[]))
        self.assertEqual(empty.describe_basket, "{pets=[]}")
