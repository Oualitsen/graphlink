package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.CatalogSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.CatalogService;
import dev.graphlink.javaserver.generated.services.FeedSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.FeedService;
import dev.graphlink.javaserver.generated.services.SearchResultSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.SearchResultService;
import dev.graphlink.javaserver.generated.services.ShelfSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.StoreSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.StoreService;
import dev.graphlink.javaserver.generated.types.Catalog;
import dev.graphlink.javaserver.generated.types.Feed;
import dev.graphlink.javaserver.generated.types.Product;
import dev.graphlink.javaserver.generated.types.SearchResult;
import dev.graphlink.javaserver.generated.types.Shelf;
import dev.graphlink.javaserver.generated.types.Store;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.List;

/**
 * All hoist-args resolvers in one bean. Each sub-field synthesizes its result
 * straight from the arguments so the hoisted values are directly observable.
 */
@Service
public class HoistServiceImpl implements
        CatalogService, CatalogSchemaMappingsService,
        FeedService, FeedSchemaMappingsService,
        StoreService, StoreSchemaMappingsService, ShelfSchemaMappingsService,
        SearchResultService, SearchResultSchemaMappingsService {

    // ── Catalog: many required args ──────────────────────────────────────────
    @Override
    public Mono<Catalog> catalog() {
        return Mono.just(Catalog.builder().id("cat1").build());
    }

    @Override
    public Flux<Product> catalogProducts(String category, Integer limit, Integer offset, Catalog value) {
        return Flux.fromIterable(Mock.products(category, limit, offset != null ? offset : 0));
    }

    // ── Feed: all optional / defaulted args ──────────────────────────────────
    @Override
    public Mono<Feed> feed() {
        return Mono.just(Feed.builder().id("feed1").build());
    }

    @Override
    public Flux<Product> feedItems(Integer limit, String sort, Feed value) {
        return Flux.fromIterable(Mock.products(sort != null ? sort : "item", limit != null ? limit : 10, 0));
    }

    // ── Store / Shelf: nested-depth hoisting ─────────────────────────────────
    @Override
    public Mono<Store> store() {
        return Mono.just(Store.builder().id("store1").build());
    }

    @Override
    public Flux<Shelf> storeShelves(Integer floor, Store value) {
        List<Shelf> shelves = new ArrayList<>();
        for (int i = 0; i < floor; i++) {
            shelves.add(Shelf.builder().id("shelf-" + i).build());
        }
        return Flux.fromIterable(shelves);
    }

    @Override
    public Flux<Product> shelfProducts(Integer limit, Shelf value) {
        return Flux.fromIterable(Mock.products(value.getId(), limit, 0));
    }

    // ── SearchResult: param-name collision (declared `fieldArgs`) ─────────────
    @Override
    public Mono<SearchResult> search(String fieldArgs) {
        return Mono.just(SearchResult.builder().id(fieldArgs).build());
    }

    @Override
    public Flux<Product> searchResultHits(Integer limit, SearchResult value) {
        return Flux.fromIterable(Mock.products("hit", limit, 0));
    }
}
