import { Module, Provider } from '@nestjs/common';
import { GraphLinkModule } from './generated/index.js';
import { ArticleService } from './generated/services/article-service.js';
import { AuthorService } from './generated/services/author-service.js';
import { DeleteArticleService } from './generated/services/delete-article-service.js';
import { BulkCreateService } from './generated/services/bulk-create-service.js';
import { BulkCreateGuard } from './generated/guards/bulk-create-guard.js';
import { CollideService } from './generated/services/collide-service.js';
import { StatusService } from './generated/services/status-service.js';
import { NestingService } from './generated/services/nesting-service.js';
import { ReservedFieldsService } from './generated/services/reserved-fields-service.js';
import { ErrItemService } from './generated/services/err-item-service.js';
import { GreetingService } from './generated/services/greeting-service.js';
import { GraphLinkInterceptor } from './generated/interfaces/graph-link-interceptor.js';
import { TeamService } from './generated/services/team-service.js';
import { TeamSchemaMappingsService } from './generated/services/team-schema-mappings-service.js';
import { RestItemService } from './generated/services/rest-item-service.js';
import { RestUploadInfoService } from './generated/services/rest-upload-info-service.js';
import { RestUploadOptionalService } from './generated/services/rest-upload-optional-service.js';
import { RestKeywordsService } from './generated/services/rest-keywords-service.js';
import { RestScalarsService } from './generated/services/rest-scalars-service.js';
import { RestSearchService } from './generated/services/rest-search-service.js';
import { RestTagsService } from './generated/services/rest-tags-service.js';
import { RestGreetingService } from './generated/services/rest-greeting-service.js';
import { RestPlainService } from './generated/services/rest-plain-service.js';
import { RestCountService } from './generated/services/rest-count-service.js';
import { RestFlagService } from './generated/services/rest-flag-service.js';
import { RestDownloadService } from './generated/services/rest-download-service.js';
import { RestDownloadOptionalService } from './generated/services/rest-download-optional-service.js';
import { RestDownloadLargeService } from './generated/services/rest-download-large-service.js';
import { RestFormEchoService } from './generated/services/rest-form-echo-service.js';
import { RestNestedService } from './generated/services/rest-nested-service.js';
import { RestWrapService } from './generated/services/rest-wrap-service.js';
import { RestWrapColorService } from './generated/services/rest-wrap-color-service.js';
import { RestWrapTextService } from './generated/services/rest-wrap-text-service.js';
import { RestInterceptedVoidService } from './generated/services/rest-intercepted-void-service.js';
import { RestMarkedService } from './generated/services/rest-marked-service.js';
import { RestFormOptionalService } from './generated/services/rest-form-optional-service.js';
import { RestColorsService } from './generated/services/rest-colors-service.js';
import { RestHeadersService } from './generated/services/rest-headers-service.js';
import { RestDeleteService } from './generated/services/rest-delete-service.js';
import { RestOptionalBodyService } from './generated/services/rest-optional-body-service.js';
import { RestValidatedService } from './generated/services/rest-validated-service.js';
import { RestValidatedGuard } from './generated/guards/rest-validated-guard.js';
import { AuthorSchemaMappingsService } from './generated/services/author-schema-mappings-service.js';
import { ConfigService } from './generated/services/config-service.js';
import { RangeService } from './generated/services/range-service.js';
import { GreetService } from './generated/services/greet-service.js';
import { EchoPriorityService } from './generated/services/echo-priority-service.js';
import { AckPriorityService } from './generated/services/ack-priority-service.js';
import { CatalogService } from './generated/services/catalog-service.js';
import { FeedService } from './generated/services/feed-service.js';
import { StoreService } from './generated/services/store-service.js';
import { SearchResultService } from './generated/services/search-result-service.js';
import { CatalogSchemaMappingsService } from './generated/services/catalog-schema-mappings-service.js';
import { FeedSchemaMappingsService } from './generated/services/feed-schema-mappings-service.js';
import { StoreSchemaMappingsService } from './generated/services/store-schema-mappings-service.js';
import { ShelfSchemaMappingsService } from './generated/services/shelf-schema-mappings-service.js';
import { SearchResultSchemaMappingsService } from './generated/services/search-result-schema-mappings-service.js';
import { MessageService } from './generated/services/message-service.js';
import { MessageReadSchemaMappingsService } from './generated/services/message-read-schema-mappings-service.js';
import { ArticleSchemaMappingsService } from './generated/services/article-schema-mappings-service.js';
import { ArticleWithCountSchemaMappingsService } from './generated/services/article-with-count-schema-mappings-service.js';
import { ArticleServiceImpl} from './impl/article-service.js';
import { ArticleSchemaMappingsServiceImpl} from './impl/article-schema-mappings-service.js';
import { AuthorServiceImpl} from './impl/author-service.js';
import { AuthorSchemaMappingsServiceImpl} from './impl/author-schema-mappings-service.js';
import { BulkCreateServiceImpl, BulkCreateGuardImpl} from './impl/bulk-create-service.js';
import { CollideServiceImpl} from './impl/collide-service.js';
import { DefaultsServiceImpl} from './impl/defaults-service.js';
import { DeleteArticleServiceImpl} from './impl/delete-article-service.js';
import { ErrItemServiceImpl } from './impl/err-service.js';
import { GreetingServiceImpl} from './impl/greeting-service.js';
import { HoistServiceImpl} from './impl/hoist-service.js';
import { InterceptorImpl} from './impl/interceptor.js';
import { MessageServiceImpl} from './impl/message-service.js';
import { NestingServiceImpl} from './impl/nesting-service.js';
import { ReservedFieldsServiceImpl} from './impl/reserved-fields-service.js';
import {
  RestColorsServiceImpl,
  RestCountServiceImpl,
  RestDeleteServiceImpl,
  RestFlagServiceImpl,
  RestDownloadLargeServiceImpl,
  RestDownloadOptionalServiceImpl,
  RestDownloadServiceImpl,
  RestFormEchoServiceImpl,
  RestNestedServiceImpl,
  RestWrapColorServiceImpl,
  RestWrapServiceImpl,
  RestWrapTextServiceImpl,
  RestInterceptedVoidServiceImpl,
  RestMarkedServiceImpl,
  RestFormOptionalServiceImpl,
  RestGreetingServiceImpl,
  RestHeadersServiceImpl,
  RestItemServiceImpl,
  RestKeywordsServiceImpl,
  RestOptionalBodyServiceImpl,
  RestPlainServiceImpl,
  RestScalarsServiceImpl,
  RestSearchServiceImpl,
  RestTagsServiceImpl,
  RestUploadInfoServiceImpl,
  RestUploadOptionalServiceImpl,
  RestValidatedGuardImpl,
  RestValidatedServiceImpl,} from './impl/rest-impl.js';
import { StatusServiceImpl} from './impl/status-service.js';
import { TeamServiceImpl, TeamSchemaMappingsServiceImpl} from './impl/team-service.js';

const providers: Provider[] = [
  { provide: ArticleService, useClass: ArticleServiceImpl },
  { provide: AuthorService, useClass: AuthorServiceImpl },
  { provide: DeleteArticleService, useClass: DeleteArticleServiceImpl },
  { provide: BulkCreateService, useClass: BulkCreateServiceImpl },
  { provide: BulkCreateGuard, useClass: BulkCreateGuardImpl },
  { provide: CollideService, useClass: CollideServiceImpl },
  { provide: StatusService, useClass: StatusServiceImpl },
  { provide: NestingService, useClass: NestingServiceImpl },
  { provide: ReservedFieldsService, useClass: ReservedFieldsServiceImpl },
  { provide: ErrItemService, useClass: ErrItemServiceImpl },
  { provide: GreetingService, useClass: GreetingServiceImpl },
  { provide: GraphLinkInterceptor, useClass: InterceptorImpl },
  { provide: TeamService, useClass: TeamServiceImpl },
  { provide: TeamSchemaMappingsService, useClass: TeamSchemaMappingsServiceImpl },
  { provide: RestItemService, useClass: RestItemServiceImpl },
  { provide: RestUploadInfoService, useClass: RestUploadInfoServiceImpl },
  { provide: RestUploadOptionalService, useClass: RestUploadOptionalServiceImpl },
  { provide: RestKeywordsService, useClass: RestKeywordsServiceImpl },
  { provide: RestScalarsService, useClass: RestScalarsServiceImpl },
  { provide: RestSearchService, useClass: RestSearchServiceImpl },
  { provide: RestTagsService, useClass: RestTagsServiceImpl },
  { provide: RestGreetingService, useClass: RestGreetingServiceImpl },
  { provide: RestPlainService, useClass: RestPlainServiceImpl },
  { provide: RestCountService, useClass: RestCountServiceImpl },
  { provide: RestFlagService, useClass: RestFlagServiceImpl },
  { provide: RestDownloadService, useClass: RestDownloadServiceImpl },
  { provide: RestDownloadOptionalService, useClass: RestDownloadOptionalServiceImpl },
  { provide: RestDownloadLargeService, useClass: RestDownloadLargeServiceImpl },
  { provide: RestFormEchoService, useClass: RestFormEchoServiceImpl },
  { provide: RestNestedService, useClass: RestNestedServiceImpl },
  { provide: RestWrapService, useClass: RestWrapServiceImpl },
  { provide: RestWrapColorService, useClass: RestWrapColorServiceImpl },
  { provide: RestWrapTextService, useClass: RestWrapTextServiceImpl },
  { provide: RestInterceptedVoidService, useClass: RestInterceptedVoidServiceImpl },
  { provide: RestMarkedService, useClass: RestMarkedServiceImpl },
  { provide: RestFormOptionalService, useClass: RestFormOptionalServiceImpl },
  { provide: RestColorsService, useClass: RestColorsServiceImpl },
  { provide: RestHeadersService, useClass: RestHeadersServiceImpl },
  { provide: RestDeleteService, useClass: RestDeleteServiceImpl },
  { provide: RestOptionalBodyService, useClass: RestOptionalBodyServiceImpl },
  { provide: RestValidatedService, useClass: RestValidatedServiceImpl },
  { provide: RestValidatedGuard, useClass: RestValidatedGuardImpl },
  { provide: AuthorSchemaMappingsService, useClass: AuthorSchemaMappingsServiceImpl },
  DefaultsServiceImpl,
  HoistServiceImpl,
  MessageServiceImpl,
  ArticleSchemaMappingsServiceImpl,
  { provide: ConfigService, useExisting: DefaultsServiceImpl },
  { provide: RangeService, useExisting: DefaultsServiceImpl },
  { provide: GreetService, useExisting: DefaultsServiceImpl },
  { provide: EchoPriorityService, useExisting: DefaultsServiceImpl },
  { provide: AckPriorityService, useExisting: DefaultsServiceImpl },
  { provide: CatalogService, useExisting: HoistServiceImpl },
  { provide: FeedService, useExisting: HoistServiceImpl },
  { provide: StoreService, useExisting: HoistServiceImpl },
  { provide: SearchResultService, useExisting: HoistServiceImpl },
  { provide: CatalogSchemaMappingsService, useExisting: HoistServiceImpl },
  { provide: FeedSchemaMappingsService, useExisting: HoistServiceImpl },
  { provide: StoreSchemaMappingsService, useExisting: HoistServiceImpl },
  { provide: ShelfSchemaMappingsService, useExisting: HoistServiceImpl },
  { provide: SearchResultSchemaMappingsService, useExisting: HoistServiceImpl },
  { provide: MessageService, useExisting: MessageServiceImpl },
  { provide: MessageReadSchemaMappingsService, useExisting: MessageServiceImpl },
  { provide: ArticleSchemaMappingsService, useExisting: ArticleSchemaMappingsServiceImpl },
  { provide: ArticleWithCountSchemaMappingsService, useExisting: ArticleSchemaMappingsServiceImpl },
];

@Module({
  providers,
  exports: providers.map((provider) => ('provide' in provider ? provider.provide : provider)),
})
export class ServicesModule {}

@Module({ imports: [GraphLinkModule.forRoot({ imports: [ServicesModule] })] })
export class AppModule {}
