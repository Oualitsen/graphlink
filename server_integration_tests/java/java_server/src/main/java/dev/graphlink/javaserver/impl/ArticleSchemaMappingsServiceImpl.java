package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.ArticleSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;

@Service
public class ArticleSchemaMappingsServiceImpl implements ArticleSchemaMappingsService {

    @Override
    public Author articleAuthor(Article value) {
        return Data.authors.stream()
            .filter(a -> a.getId().equals(value.getAuthorId()))
            .findFirst()
            .orElse(null);
    }
}
