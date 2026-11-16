from typing import List

from generated.context import GraphLinkContext
from generated.types.catalog import Catalog
from generated.types.feed import Feed
from generated.types.product import Product
from generated.types.search_result import SearchResult
from generated.types.shelf import Shelf
from generated.types.store import Store


def products(prefix: str, count: int, offset: int) -> List[Product]:
    return [Product(id=f"{prefix}-{offset + i}", name=f"{prefix}-{offset + i}") for i in range(count)]


class HoistServiceImpl:
    async def catalog(self, context: GraphLinkContext) -> Catalog:
        return Catalog(id="cat1")

    async def catalog_products(self, category: str, limit: int, offset, value: Catalog, context: GraphLinkContext) -> List[Product]:
        return products(category, limit, offset or 0)

    async def feed(self, context: GraphLinkContext) -> Feed:
        return Feed(id="feed1")

    async def feed_items(self, limit, sort, value: Feed, context: GraphLinkContext) -> List[Product]:
        return products(sort if sort is not None else "item", limit if limit is not None else 10, 0)

    async def store(self, context: GraphLinkContext) -> Store:
        return Store(id="store1")

    async def store_shelves(self, floor: int, value: Store, context: GraphLinkContext) -> List[Shelf]:
        return [Shelf(id=f"shelf-{i}") for i in range(floor)]

    async def shelf_products(self, limit: int, value: Shelf, context: GraphLinkContext) -> List[Product]:
        return products(value.id, limit, 0)

    async def search(self, field_args: str, context: GraphLinkContext) -> SearchResult:
        return SearchResult(id=field_args)

    async def search_result_hits(self, limit: int, value: SearchResult, context: GraphLinkContext) -> List[Product]:
        return products("hit", limit, 0)
