package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.services.CatalogSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.CatalogService
import dev.graphlink.kotlinserverblocking.generated.services.FeedSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.FeedService
import dev.graphlink.kotlinserverblocking.generated.services.SearchResultSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.SearchResultService
import dev.graphlink.kotlinserverblocking.generated.services.ShelfSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.StoreSchemaMappingsService
import dev.graphlink.kotlinserverblocking.generated.services.StoreService
import dev.graphlink.kotlinserverblocking.generated.types.Catalog
import dev.graphlink.kotlinserverblocking.generated.types.Feed
import dev.graphlink.kotlinserverblocking.generated.types.Product
import dev.graphlink.kotlinserverblocking.generated.types.SearchResult
import dev.graphlink.kotlinserverblocking.generated.types.Shelf
import dev.graphlink.kotlinserverblocking.generated.types.Store
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
    override fun catalog(): Catalog = Catalog(id = "cat1")

    override fun catalogProducts(category: String, limit: Int, offset: Int?, value: Catalog): List<Product> =
        Mock.products(category, limit, offset ?: 0)

    // ── Feed: all optional / defaulted args ──────────────────────────────────
    override fun feed(): Feed = Feed(id = "feed1")

    override fun feedItems(limit: Int?, sort: String?, value: Feed): List<Product> =
        Mock.products(sort ?: "item", limit ?: 10, 0)

    // ── Store / Shelf: nested-depth hoisting ─────────────────────────────────
    override fun store(): Store = Store(id = "store1")

    override fun storeShelves(floor: Int, value: Store): List<Shelf> =
        (0 until floor).map { Shelf(id = "shelf-$it") }

    override fun shelfProducts(limit: Int, value: Shelf): List<Product> =
        Mock.products(value.id, limit, 0)

    // ── SearchResult: param-name collision (declared `fieldArgs`) ─────────────
    override fun search(fieldArgs: String): SearchResult = SearchResult(id = fieldArgs)

    override fun searchResultHits(limit: Int, value: SearchResult): List<Product> =
        Mock.products("hit", limit, 0)
}
