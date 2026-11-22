import './impl/my-context.js';
import { createServer } from './generated/index.js';
import { ArticleServiceImpl } from './impl/article-service.js';
import { ArticleSchemaMappingsServiceImpl } from './impl/article-schema-mappings-service.js';
import { AuthorServiceImpl } from './impl/author-service.js';
import { AuthorSchemaMappingsServiceImpl } from './impl/author-schema-mappings-service.js';
import { BulkCreateServiceImpl, BulkCreateGuardImpl } from './impl/bulk-create-service.js';
import { CollideServiceImpl } from './impl/collide-service.js';
import { DefaultsServiceImpl } from './impl/defaults-service.js';
import { DeleteArticleServiceImpl } from './impl/delete-article-service.js';
import { ErrItemServiceImpl } from './impl/err-service.js';
import { GreetingServiceImpl } from './impl/greeting-service.js';
import { HoistServiceImpl } from './impl/hoist-service.js';
import { InterceptorImpl } from './impl/interceptor.js';
import { MessageServiceImpl } from './impl/message-service.js';
import { NestingServiceImpl } from './impl/nesting-service.js';
import { ReservedFieldsServiceImpl } from './impl/reserved-fields-service.js';
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
  RestValidatedServiceImpl,
} from './impl/rest-impl.js';
import { StatusServiceImpl } from './impl/status-service.js';
import { TeamServiceImpl, TeamSchemaMappingsServiceImpl } from './impl/team-service.js';

const PORT = 9997;

// Grouped beans, each implementing several generated service interfaces, are
// shared across every slot they satisfy — mirrors the Kotlin/Spring wiring.
const defaults = new DefaultsServiceImpl();
const hoist = new HoistServiceImpl();
const message = new MessageServiceImpl();
const articleMappings = new ArticleSchemaMappingsServiceImpl();

const httpServer = await createServer({
  articleService: new ArticleServiceImpl(),
  authorService: new AuthorServiceImpl(),
  deleteArticleService: new DeleteArticleServiceImpl(),
  bulkCreateService: new BulkCreateServiceImpl(),
  bulkCreateGuard: new BulkCreateGuardImpl(),
  collideService: new CollideServiceImpl(),
  statusService: new StatusServiceImpl(),
  nestingService: new NestingServiceImpl(),
  reservedFieldsService: new ReservedFieldsServiceImpl(),
  errItemService: new ErrItemServiceImpl(),
  greetingService: new GreetingServiceImpl(),
  interceptor: new InterceptorImpl(),
  teamService: new TeamServiceImpl(),
  teamSchemaMappingsService: new TeamSchemaMappingsServiceImpl(),

  restItemService: new RestItemServiceImpl(),
  restUploadInfoService: new RestUploadInfoServiceImpl(),
  restUploadOptionalService: new RestUploadOptionalServiceImpl(),
  restKeywordsService: new RestKeywordsServiceImpl(),
  restScalarsService: new RestScalarsServiceImpl(),
  restSearchService: new RestSearchServiceImpl(),
  restTagsService: new RestTagsServiceImpl(),
  restGreetingService: new RestGreetingServiceImpl(),
  restPlainService: new RestPlainServiceImpl(),
  restCountService: new RestCountServiceImpl(),
  restFlagService: new RestFlagServiceImpl(),
  restDownloadService: new RestDownloadServiceImpl(),
  restDownloadOptionalService: new RestDownloadOptionalServiceImpl(),
  restDownloadLargeService: new RestDownloadLargeServiceImpl(),
  restFormEchoService: new RestFormEchoServiceImpl(),
  restNestedService: new RestNestedServiceImpl(),
  restWrapService: new RestWrapServiceImpl(),
  restWrapColorService: new RestWrapColorServiceImpl(),
  restWrapTextService: new RestWrapTextServiceImpl(),
  restInterceptedVoidService: new RestInterceptedVoidServiceImpl(),
  restMarkedService: new RestMarkedServiceImpl(),
  restFormOptionalService: new RestFormOptionalServiceImpl(),
  restColorsService: new RestColorsServiceImpl(),
  restHeadersService: new RestHeadersServiceImpl(),
  restDeleteService: new RestDeleteServiceImpl(),
  restOptionalBodyService: new RestOptionalBodyServiceImpl(),
  restValidatedService: new RestValidatedServiceImpl(),
  restValidatedGuard: new RestValidatedGuardImpl(),

  configService: defaults,
  rangeService: defaults,
  greetService: defaults,
  echoPriorityService: defaults,
  ackPriorityService: defaults,

  catalogService: hoist,
  feedService: hoist,
  storeService: hoist,
  searchResultService: hoist,
  catalogSchemaMappingsService: hoist,
  feedSchemaMappingsService: hoist,
  storeSchemaMappingsService: hoist,
  shelfSchemaMappingsService: hoist,
  searchResultSchemaMappingsService: hoist,

  messageService: message,
  messageReadSchemaMappingsService: message,

  authorSchemaMappingsService: new AuthorSchemaMappingsServiceImpl(),
  articleSchemaMappingsService: articleMappings,
  articleWithCountSchemaMappingsService: articleMappings,
});

httpServer.listen(PORT, () => {
  console.log(`Server ready at http://localhost:${PORT}/graphql`);
});
