package dev.graphlink.javaserver.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.javaserver.generated.types.Article;
import dev.graphlink.javaserver.generated.types.Author;
import reactor.core.publisher.Sinks;

import java.io.File;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

public class Data {
    public static final List<Author> authors;
    public static final List<Article> articles;
    private static final AtomicInteger nextId;

    static {
        try {
            String fixturesPath = System.getenv().getOrDefault("FIXTURES_PATH", "../../fixtures.json");
            @SuppressWarnings("unchecked")
            Map<String, Object> fixtures = new ObjectMapper().readValue(new File(fixturesPath), Map.class);

            @SuppressWarnings("unchecked")
            List<Map<String, String>> authorsData = (List<Map<String, String>>) fixtures.get("authors");
            @SuppressWarnings("unchecked")
            List<Map<String, String>> articlesData = (List<Map<String, String>>) fixtures.get("articles");

            authors = Collections.synchronizedList(new ArrayList<>(
                authorsData.stream()
                    .map(a -> Author.builder().id(a.get("id")).name(a.get("name")).build())
                    .collect(Collectors.toList())
            ));
            articles = Collections.synchronizedList(new ArrayList<>(
                articlesData.stream()
                    .map(a -> Article.builder().id(a.get("id")).title(a.get("title")).authorId(a.get("authorId")).build())
                    .collect(Collectors.toList())
            ));
            nextId = new AtomicInteger((Integer) fixtures.get("nextId"));
        } catch (Exception e) {
            throw new RuntimeException("Failed to load ../../fixtures.json", e);
        }
    }

    public static String nextId() {
        return String.valueOf(nextId.getAndIncrement());
    }

    public static final Sinks.Many<Article> articleCreatedSink =
        Sinks.many().multicast().onBackpressureBuffer();

    public static final Sinks.Many<Article> articleUpdatedSink =
        Sinks.many().multicast().onBackpressureBuffer();
}
