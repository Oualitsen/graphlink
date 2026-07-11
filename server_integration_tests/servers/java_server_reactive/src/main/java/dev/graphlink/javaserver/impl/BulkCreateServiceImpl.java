package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.services.BulkCreateService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.List;

@Service
public class BulkCreateServiceImpl implements BulkCreateService {

    @Override
    public Mono<Integer> bulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        int count = 0;
        return Mono.just(count);
    }

    @Override
    public Mono<Void> validateBulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        return Mono.empty();
    }
}
