from impl.core import (
    ArticleSchemaMappingsServiceImpl,
    ArticleServiceImpl,
    AuthorSchemaMappingsServiceImpl,
    AuthorServiceImpl,
    BulkCreateGuardImpl,
    BulkCreateServiceImpl,
    CollideServiceImpl,
    DefaultsServiceImpl,
    DeleteArticleServiceImpl,
    GreetingServiceImpl,
    MessageServiceImpl,
    NestingServiceImpl,
    ReservedFieldsServiceImpl,
    StatusServiceImpl,
    TeamSchemaMappingsServiceImpl,
    TeamServiceImpl,
)
from impl.hoist import (
    HoistServiceImpl,
)


def graphql_services():
    defaults = DefaultsServiceImpl()
    hoist = HoistServiceImpl()
    message = MessageServiceImpl()
    article_mappings = ArticleSchemaMappingsServiceImpl()
    return dict(
        article_service=ArticleServiceImpl(),
        author_service=AuthorServiceImpl(),
        delete_article_service=DeleteArticleServiceImpl(),
        bulk_create_service=BulkCreateServiceImpl(),
        bulk_create_guard=BulkCreateGuardImpl(),
        collide_service=CollideServiceImpl(),
        status_service=StatusServiceImpl(),
        nesting_service=NestingServiceImpl(),
        reserved_fields_service=ReservedFieldsServiceImpl(),
        greeting_service=GreetingServiceImpl(),
        team_service=TeamServiceImpl(),
        team_schema_mappings_service=TeamSchemaMappingsServiceImpl(),
        config_service=defaults,
        range_service=defaults,
        greet_service=defaults,
        echo_priority_service=defaults,
        ack_priority_service=defaults,
        catalog_service=hoist,
        feed_service=hoist,
        store_service=hoist,
        search_result_service=hoist,
        catalog_schema_mappings_service=hoist,
        feed_schema_mappings_service=hoist,
        store_schema_mappings_service=hoist,
        shelf_schema_mappings_service=hoist,
        search_result_schema_mappings_service=hoist,
        message_service=message,
        message_read_schema_mappings_service=message,
        author_schema_mappings_service=AuthorSchemaMappingsServiceImpl(),
        article_schema_mappings_service=article_mappings,
        article_with_count_schema_mappings_service=article_mappings,
    )
