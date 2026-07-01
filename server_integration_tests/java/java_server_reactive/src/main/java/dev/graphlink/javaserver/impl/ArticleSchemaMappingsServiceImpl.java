package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.ArticleSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class ArticleSchemaMappingsServiceImpl implements ArticleSchemaMappingsService {

    @Override
    public Mono<Author> articleAuthor(Article value) {
        var result =  Data.authors.stream()
            .filter(a -> a.getId().equals(value.getAuthorId()))
            .findFirst()
            .orElse(null);
        return Mono.just(result);
    }
}
