package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.services.BulkCreateService;
import dev.graphlink.javaserver.generated.types.Article;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.List;

@Service
public class BulkCreateServiceImpl implements BulkCreateService {

    @Override
    public Mono<Integer> bulkCreate(List<? extends List<? extends List<CreateArticleInput>>> matrix) {
        if (matrix == null) return Mono.just(0);
        int count = 0;
        for (var group : matrix) {
            if (group == null) continue;
            for (var batch : group) {
                if (batch == null) continue;
                for (var input : batch) {
                    if (input != null) {
                        var article = Article.builder()
                            .id(Data.nextId())
                            .title(input.getTitle())
                            .authorId(input.getAuthorId())
                            .build();
                        Data.articles.add(article);
                        count++;
                    }
                }
            }
        }
        return Mono.just(count);
    }

    @Override
    public Mono<Void> validateBulkCreate(List<? extends List<? extends List<CreateArticleInput>>> matrix) {
        return Mono.empty();
    }
}
