package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.interfaces.Article;
import dev.graphlink.javaserver.generated.services.AuthorSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import graphql.GraphQLContext;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class AuthorSchemaMappingsServiceImpl implements AuthorSchemaMappingsService {

    @Override
    public Mono<Map<Author, List<Article>>> authorArticles(List<Author> value, GraphQLContext graphQLContext) {
        Map<Author, List<Article>> result = new HashMap<>();
        for (Author author : value) {
            List<Article> articles = Data.articles.stream()
                .filter(a -> a.getAuthorId().equals(author.getId()))
                .collect(Collectors.toList());
            result.put(author, articles);
        }
        return Mono.just(result);
    }

    @Override
    public Flux<Article> authorLatestArticles(Integer limit, Author value) {
        return Flux.fromIterable(Data.articles.stream()
            .filter(a -> a.getAuthorId().equals(value.getId()))
            .limit(limit)
            .collect(Collectors.toList()));
    }
}
