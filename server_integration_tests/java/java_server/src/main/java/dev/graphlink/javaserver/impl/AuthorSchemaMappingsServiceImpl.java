package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.interfaces.GlArticleProjection;
import dev.graphlink.javaserver.generated.services.AuthorSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import graphql.GraphQLContext;

import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class AuthorSchemaMappingsServiceImpl implements AuthorSchemaMappingsService {

    @Override
     public Map<Author, List<GlArticleProjection>> authorArticles(List<Author> value, GraphQLContext graphQLContext) {
        Map<Author, List<GlArticleProjection>> result = new HashMap<>();
        for (Author author : value) {
            List<GlArticleProjection> articles = Data.articles.stream()
                .filter(a -> a.getAuthorId().equals(author.getId()))
                .collect(Collectors.toList());
            result.put(author, articles);
        }
        return result;
    }

    @Override
    public List<Article> authorLatestArticles(int limit, Author value) {
        return Data.articles.stream()
            .filter(a -> a.getAuthorId().equals(value.getId()))
            .limit(limit)
            .collect(Collectors.toList());
    }
}
