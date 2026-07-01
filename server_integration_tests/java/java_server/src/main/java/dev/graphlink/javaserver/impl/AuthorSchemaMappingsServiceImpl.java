package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.AuthorSchemaMappingsService;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class AuthorSchemaMappingsServiceImpl implements AuthorSchemaMappingsService {

    @Override
    public Map<Author, ? extends List<Article>> authorArticles(List<Author> value) {
        System.out.println("class = " + value.getFirst().getClass());
        Map<Author, List<Article>> result = new HashMap<>();
        for (Author author : value) {
            List<Article> articles = Data.articles.stream()
                .filter(a -> a.getAuthorId().equals(author.getId()))
                .collect(Collectors.toList());
            result.put(author, articles);
        }
        return result;
    }

    @Override
    public List<Article> authorLatestArticles(Author value, Integer limit) {
        return Data.articles.stream()
            .filter(a -> a.getAuthorId().equals(value.getId()))
            .limit(limit)
            .collect(Collectors.toList());
    }
}
