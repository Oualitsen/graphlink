import unittest

from generated import CatalogFieldArgs1, FeedFieldArgs, SearchFieldArgs, StoreFieldArgs

from .fixtures import new_client


class HoistArgsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_many_required_hoisted_args_input_renamed_on_collision(self) -> None:
        catalog = (await self.client.queries.catalog(
            field_args=CatalogFieldArgs1(products_category="books", products_limit=3, products_offset=0)
        )).catalog
        self.assertEqual(len(catalog.products), 3)
        self.assertTrue(all(p.name.startswith("books") for p in catalog.products))

    async def test_all_optional_hoisted_args_can_be_omitted(self) -> None:
        self.assertEqual(len((await self.client.queries.feed()).feed.items), 10)

    async def test_optional_hoisted_args_can_be_supplied(self) -> None:
        feed = (await self.client.queries.feed(field_args=FeedFieldArgs(items_limit=4, items_sort="z"))).feed
        self.assertEqual(len(feed.items), 4)
        self.assertTrue(feed.items[0].name.startswith("z"))

    async def test_nested_depth_hoisting_collapses_into_one_input(self) -> None:
        store = (await self.client.queries.store(field_args=StoreFieldArgs(shelves_floor=2, products_limit=3))).store
        self.assertEqual(len(store.shelves), 2)
        self.assertEqual(len(store.shelves[0].products), 3)

    async def test_param_name_collision_uses_field_args1_for_synthetic_arg(self) -> None:
        search = (await self.client.queries.search(field_args="q", field_args1=SearchFieldArgs(hits_limit=3))).search
        self.assertEqual((search.id, len(search.hits)), ("q", 3))
