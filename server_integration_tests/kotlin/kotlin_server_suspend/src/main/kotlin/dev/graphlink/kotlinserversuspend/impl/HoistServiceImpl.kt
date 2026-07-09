package dev.graphlink.kotlinserversuspend.impl

import dev.graphlink.kotlinserversuspend.generated.services.CatalogSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.CatalogService
import dev.graphlink.kotlinserversuspend.generated.services.FeedSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.FeedService
import dev.graphlink.kotlinserversuspend.generated.services.SearchResultSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.SearchResultService
import dev.graphlink.kotlinserversuspend.generated.services.ShelfSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.StoreSchemaMappingsService
import dev.graphlink.kotlinserversuspend.generated.services.StoreService
import dev.graphlink.kotlinserversuspend.generated.types.Catalog
import dev.graphlink.kotlinserversuspend.generated.types.Feed
import dev.graphlink.kotlinserversuspend.generated.types.Product
import dev.graphlink.kotlinserversuspend.generated.types.SearchResult
import dev.graphlink.kotlinserversuspend.generated.types.Shelf
import dev.graphlink.kotlinserversuspend.generated.types.Store
import org.springframework.stereotype.Service

/**
 * All hoist-args resolvers in one bean. Each sub-field synthesizes its result
 * straight from the arguments so the hoisted values are directly observable.
 */
@Service
class HoistServiceImpl :
    CatalogService, CatalogSchemaMappingsService,
    FeedService, FeedSchemaMappingsService,
    StoreService, StoreSchemaMappingsService, ShelfSchemaMappingsService,
    SearchResultService, SearchResultSchemaMappingsService {

    // ── Catalog: many required args ──────────────────────────────────────────
    override suspend fun catalog(): Catalog = Catalog(id = "cat1")

    override suspend fun catalogProducts(category: String, limit: Int, offset: Int?, value: Catalog): List<Product> =
        Mock.products(category, limit, offset ?: 0)

    // ── Feed: all optional / defaulted args ──────────────────────────────────
    override suspend fun feed(): Feed = Feed(id = "feed1")

    override suspend fun feedItems(limit: Int?, sort: String?, value: Feed): List<Product> =
        Mock.products(sort ?: "item", limit ?: 10, 0)

    // ── Store / Shelf: nested-depth hoisting ─────────────────────────────────
    override suspend fun store(): Store = Store(id = "store1")

    override suspend fun storeShelves(floor: Int, value: Store): List<Shelf> =
        (0 until floor).map { Shelf(id = "shelf-$it") }

    override suspend fun shelfProducts(limit: Int, value: Shelf): List<Product> =
        Mock.products(value.id, limit, 0)

    // ── SearchResult: param-name collision (declared `fieldArgs`) ─────────────
    override suspend fun search(fieldArgs: String): SearchResult = SearchResult(id = fieldArgs)

    override suspend fun searchResultHits(limit: Int, value: SearchResult): List<Product> =
        Mock.products("hit", limit, 0)
}
