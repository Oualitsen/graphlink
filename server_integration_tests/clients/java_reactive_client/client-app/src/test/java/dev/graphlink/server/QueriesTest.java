package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.inputs.GetArticleFieldArgs;
import dev.graphlink.server.generated.inputs.GetAuthorAndArticleFieldArgs;
import dev.graphlink.server.generated.inputs.GetAuthorFieldArgs;
import dev.graphlink.server.generated.inputs.ListArticlesFieldArgs;
import dev.graphlink.server.generated.inputs.ListAuthorsFieldArgs;
import dev.graphlink.server.generated.types.Article;
import dev.graphlink.server.generated.types.Author;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;

public class QueriesTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Nested
    class GetAuthor {
        @Test
        void returnsAuthorById() {
            var res = client.queries.getAuthor("1", new GetAuthorFieldArgs(10)).block();
            assertNotNull(res.getGetAuthor());
            assertEquals("1", res.getGetAuthor().getId());
            assertEquals("Ramdane", res.getGetAuthor().getName());
        }

        @Test
        void returnsNullForUnknownId() {
            var res = client.queries.getAuthor("missing", new GetAuthorFieldArgs(10)).block();
            assertNull(res.getGetAuthor());
        }

        @Test
        void articlesResolvedViaBatchDataLoaderMapping() {
            var res = client.queries.getAuthor("1", new GetAuthorFieldArgs(10)).block();
            Set<String> titles = res.getGetAuthor().getArticles().stream()
                    .map(Article::getTitle).collect(Collectors.toSet());
            assertTrue(titles.containsAll(List.of("GraphLink Basics", "Advanced GraphLink")));
        }

        @Test
        void latestArticlesResolvedViaNonBatchMappingWithArguments() {
            var res = client.queries.getAuthor("1", new GetAuthorFieldArgs(10)).block();
            Set<String> titles = res.getGetAuthor().getLatestArticles().stream()
                    .map(Article::getTitle).collect(Collectors.toSet());
            assertTrue(titles.containsAll(List.of("GraphLink Basics", "Advanced GraphLink")));
        }
    }

    @Nested
    class GetAuthorWithoutArticle {
        @Test
        void doesNotRequireLimitArgumentWhenArticlesNotProjected() {
            var res = client.queries.getAuthorWithoutArticle("1").block();
            assertNotNull(res.getGetAuthor());
            assertEquals("1", res.getGetAuthor().getId());
            assertEquals("Ramdane", res.getGetAuthor().getName());
        }
    }

    @Nested
    class GetArticle {
        @Test
        void returnsArticleById() {
            var res = client.queries.getArticle("1", new GetArticleFieldArgs(2)).block();
            assertEquals("1", res.getGetArticle().getId());
            assertEquals("GraphLink Basics", res.getGetArticle().getTitle());
        }

        @Test
        void authorResolvedViaNonBatchSchemaMapping() {
            var res = client.queries.getArticle("1", new GetArticleFieldArgs(2)).block();
            assertEquals("1", res.getGetArticle().getAuthor().getId());
            assertEquals("Ramdane", res.getGetArticle().getAuthor().getName());
        }
    }

    @Nested
    class GetAuthorAndArticle {
        @Test
        void resolvesBothRootFieldsWithOwnArgsPlusSharedFragmentArgument() {
            var res = client.queries.getAuthorAndArticle("1", "3", new GetAuthorAndArticleFieldArgs(1)).block();
            assertEquals("1", res.getAuthor().getId());
            assertEquals(1, res.getAuthor().getLatestArticles().size());
            assertEquals("3", res.getArticle().getId());
            assertEquals("Alice's First Post", res.getArticle().getTitle());
        }
    }

    @Nested
    class ListAuthorsAndListArticles {
        @Test
        void listAuthorsReturnsAllAuthors() {
            var res = client.queries.listAuthors(new ListAuthorsFieldArgs(10)).block();
            List<String> ids = res.getListAuthors().stream().map(Author::getId).collect(Collectors.toList());
            assertTrue(ids.containsAll(List.of("1", "2")));
        }

        @Test
        void listArticlesReturnsAllArticles() {
            var res = client.queries.listArticles(new ListArticlesFieldArgs(2)).block();
            List<String> ids = res.getListArticles().stream().map(Article::getId).collect(Collectors.toList());
            assertTrue(ids.contains("1"));
        }
    }
}
