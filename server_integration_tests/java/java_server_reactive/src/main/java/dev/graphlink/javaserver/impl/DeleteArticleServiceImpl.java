package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.DeleteArticleService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class DeleteArticleServiceImpl implements DeleteArticleService {

    @Override
    public Mono<Boolean> deleteArticle(String id) {
        return Mono.just(Data.articles.removeIf(a -> a.getId().equals(id)));
    }
}
