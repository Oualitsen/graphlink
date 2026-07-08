package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.ArticleType;
import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.inputs.UpdateArticleInput;
import dev.graphlink.javaserver.generated.interfaces.GlArticleProjection;
import dev.graphlink.javaserver.generated.services.ArticleService;
import dev.graphlink.javaserver.generated.types.Article;
import graphql.GraphQLContext;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.NoSuchElementException;

@Service
public class ArticleServiceImpl implements ArticleService {

    @Override
    public Mono<Article> getArticle(String id) {
        return Mono.justOrEmpty(Data.articles.stream().filter(a -> a.getId().equals(id)).findFirst().orElse(null));
    }

    @Override
    public Flux<Article> listArticles() {
        return Flux.fromIterable(new ArrayList<>(Data.articles));
    }

    @Override
    public Mono<Article> createArticle(CreateArticleInput input) {
        System.out.println("Creating article");
        var article = Article.builder()
            .id(Data.nextId())
            .title(input.getTitle())
            .authorId(input.getAuthorId())
            .published(false)
            .build();
        Data.articles.add(article);
        Data.articleCreatedSink.tryEmitNext(article);
        return Mono.just(article);
    }

    @Override
    public Mono<Article> updateArticle(UpdateArticleInput input) {
        for (int i = 0; i < Data.articles.size(); i++) {
            var a = Data.articles.get(i);
            if (a.getId().equals(input.getId())) {
                var updated = Article.builder()
                    .id(a.getId())
                    .title(input.getTitle() != null ? input.getTitle() : a.getTitle())
                    .type(a.getType())
                    .authorId(a.getAuthorId())
                    .webSite(a.getWebSite())
                    .published(a.getPublished())
                    .build();
                Data.articles.set(i, updated);
                Data.articleUpdatedSink.tryEmitNext(updated);
                return Mono.just(updated);
            }
        }
        return Mono.error(new NoSuchElementException("Article not found: " + input.getId()));
    }

    @Override
    public Flux<Article> articleCreated() {
        return Data.articleCreatedSink.asFlux();
    }

    @Override
    public Flux<Article> articleUpdated(String id) {
        return Data.articleUpdatedSink.asFlux().filter(a -> a.getId().equals(id));
    }

    @Override
    public Mono<GlArticleProjection> getProjectedArticle(GraphQLContext graphQLContext) {
        GlArticleProjection projection = Data.articles.stream().findFirst().orElse(null);
        return Mono.justOrEmpty(projection);
    }

    @Override
    public Flux<String> articleDeleted() {
        return Flux.just("deleted-1", "deleted-2");
    }

    @Override
    public Flux<ArticleType> getArticleTypes() {
        return Flux.just(ArticleType.NEWS, ArticleType.BLOG, ArticleType.REVIEW);
    }

    @Override
    public Mono<Article> getArticleWithCount() {
        return Mono.justOrEmpty(Data.articles.stream().findFirst().orElse(null));
    }

    @Override
    public Mono<GlArticleProjection> getArticleInfo(GraphQLContext graphQLContext) {
        return Mono.justOrEmpty(Data.articles.stream().findFirst().orElse(null));
    }
}
