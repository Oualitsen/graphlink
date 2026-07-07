package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.inputs.UpdateArticleInput;
import dev.graphlink.javaserver.generated.enums.ArticleType;
import dev.graphlink.javaserver.generated.interfaces.GlArticleProjection;
import dev.graphlink.javaserver.generated.services.ArticleService;
import dev.graphlink.javaserver.generated.types.Article;
import graphql.schema.DataFetchingEnvironment;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;

import java.util.ArrayList;
import java.util.List;
import java.util.NoSuchElementException;

@Service
public class ArticleServiceImpl implements ArticleService {

    @Override
    public Article getArticle(String id) {
        return Data.articles.stream().filter(a -> a.getId().equals(id)).findFirst().orElse(null);
    }

    @Override
    public List<Article> listArticles() {
        return new ArrayList<>(Data.articles);
    }

    @Override
    public Article createArticle(CreateArticleInput input) {
        var article = Article.builder()
            .id(Data.nextId())
            .title(input.getTitle())
            .authorId(input.getAuthorId())
            .build();
        Data.articles.add(article);
        Data.articleCreatedSink.tryEmitNext(article);
        return article;
    }

    @Override
    public Article updateArticle(UpdateArticleInput input) {
        for (int i = 0; i < Data.articles.size(); i++) {
            var a = Data.articles.get(i);
            if (a.getId().equals(input.getId())) {
                var updated = Article.builder()
                    .id(a.getId())
                    .title(input.getTitle() != null ? input.getTitle() : a.getTitle())
                    .authorId(a.getAuthorId())
                    .build();
                Data.articles.set(i, updated);
                Data.articleUpdatedSink.tryEmitNext(updated);
                return updated;
            }
        }
        throw new NoSuchElementException("Article not found: " + input.getId());
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
    public GlArticleProjection getProjectedArticle(DataFetchingEnvironment dataFetchingEnvironment) {
        // Article implements GlArticleProjection, so a concrete article is a
        // valid projection — the client selects whichever subset it wants.
        return Data.articles.stream().findFirst().orElse(null);
    }

    @Override
    public List<ArticleType> getArticleTypes() {
        return List.of(ArticleType.NEWS, ArticleType.BLOG, ArticleType.REVIEW);
    }

    @Override
    public Flux<String> articleDeleted() {
        return Flux.just("deleted-1", "deleted-2");
    }

    @Override
    public Article getArticleWithCount() {
        return Data.articles.stream().findFirst().orElse(null);
    }

    @Override
    public GlArticleProjection getArticleInfo(DataFetchingEnvironment dataFetchingEnvironment) {
        return Data.articles.stream().findFirst().orElse(null);
    }
}
