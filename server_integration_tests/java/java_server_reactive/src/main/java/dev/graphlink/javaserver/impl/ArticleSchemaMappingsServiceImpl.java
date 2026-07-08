package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.ArticleSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.ArticleWithCountSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.stream.Collectors;

@Service
public class ArticleSchemaMappingsServiceImpl
        implements ArticleSchemaMappingsService, ArticleWithCountSchemaMappingsService {

    @Override
    public Mono<Author> articleAuthor(Article value) {
        return Mono.justOrEmpty(Data.authors.stream()
                .filter(a -> a.getId().equals(value.getAuthorId()))
                .findFirst()
                .orElse(null));
    }

    @Override
    public Flux<Author> articleAuthorList(Article value) {
        return Flux.fromIterable(Data.authors.stream()
            .filter(a -> a.getId().equals(value.getAuthorId()))
            .collect(Collectors.toList()));
    }

    @Override
    public Mono<Integer> articleWithCountCount(Article value) {
        return Mono.just(Data.articles.indexOf(value) + 1);
    }
}
