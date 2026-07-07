package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.ArticleSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.ArticleWithCountSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class ArticleSchemaMappingsServiceImpl
        implements ArticleSchemaMappingsService, ArticleWithCountSchemaMappingsService {

    @Override
    public Author articleAuthor(Article value) {
        return Data.authors.stream()
            .filter(a -> a.getId().equals(value.getAuthorId()))
            .findFirst()
            .orElse(null);
    }

    @Override
    public List<Author> articleAuthorList(Article value) {
        return Data.authors.stream()
            .filter(a -> a.getId().equals(value.getAuthorId()))
            .collect(Collectors.toList());
    }

    @Override
    public int articleWithCountCount(Article value) {
        return Data.articles.indexOf(value) + 1;
    }
}
