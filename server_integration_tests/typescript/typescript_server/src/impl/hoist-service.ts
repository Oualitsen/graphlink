import { CatalogService } from '../generated/services/catalog-service.js';
import { CatalogSchemaMappingsService } from '../generated/services/catalog-schema-mappings-service.js';
import { FeedService } from '../generated/services/feed-service.js';
import { FeedSchemaMappingsService } from '../generated/services/feed-schema-mappings-service.js';
import { StoreService } from '../generated/services/store-service.js';
import { StoreSchemaMappingsService } from '../generated/services/store-schema-mappings-service.js';
import { ShelfSchemaMappingsService } from '../generated/services/shelf-schema-mappings-service.js';
import { SearchResultService } from '../generated/services/search-result-service.js';
import { SearchResultSchemaMappingsService } from '../generated/services/search-result-schema-mappings-service.js';
import { Catalog } from '../generated/types/catalog.js';
import { Feed } from '../generated/types/feed.js';
import { Store } from '../generated/types/store.js';
import { Shelf } from '../generated/types/shelf.js';
import { SearchResult } from '../generated/types/search-result.js';
import { Product } from '../generated/types/product.js';
import { Mock } from './mock.js';

/**
 * All hoist-args resolvers in one bean. Each sub-field synthesizes its result
 * straight from the arguments so the hoisted values are directly observable.
 */
export class HoistServiceImpl
  implements
    CatalogService,
    CatalogSchemaMappingsService,
    FeedService,
    FeedSchemaMappingsService,
    StoreService,
    StoreSchemaMappingsService,
    ShelfSchemaMappingsService,
    SearchResultService,
    SearchResultSchemaMappingsService
{
  // ── Catalog: many required args ────────────────────────────────────────────
  async catalog(): Promise<Catalog> {
    return { id: 'cat1' };
  }

  async catalogProducts(
    category: string,
    limit: number,
    offset: number | null,
    _value: Catalog,
  ): Promise<Product[]> {
    return Mock.products(category, limit, offset ?? 0);
  }

  // ── Feed: all optional / defaulted args ────────────────────────────────────
  async feed(): Promise<Feed> {
    return { id: 'feed1' };
  }

  async feedItems(limit: number | null, sort: string | null, _value: Feed): Promise<Product[]> {
    return Mock.products(sort ?? 'item', limit ?? 10, 0);
  }

  // ── Store / Shelf: nested-depth hoisting ───────────────────────────────────
  async store(): Promise<Store> {
    return { id: 'store1' };
  }

  async storeShelves(floor: number, _value: Store): Promise<Shelf[]> {
    return Array.from({ length: floor }, (_, i) => ({ id: `shelf-${i}` }));
  }

  async shelfProducts(limit: number, value: Shelf): Promise<Product[]> {
    return Mock.products(value.id, limit, 0);
  }

  // ── SearchResult: param-name collision (declared `fieldArgs`) ───────────────
  async search(fieldArgs: string): Promise<SearchResult> {
    return { id: fieldArgs };
  }

  async searchResultHits(limit: number, _value: SearchResult): Promise<Product[]> {
    return Mock.products('hit', limit, 0);
  }
}
