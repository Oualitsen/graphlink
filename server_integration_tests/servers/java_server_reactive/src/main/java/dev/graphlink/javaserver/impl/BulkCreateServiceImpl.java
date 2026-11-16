package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.services.BulkCreateService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.util.ArrayList;
import java.util.List;

// Counts the inputs it received, so a test can see how the nested list was decoded.
@Service
public class BulkCreateServiceImpl implements BulkCreateService {

    static List<CreateArticleInput> inputs(List<? extends List<CreateArticleInput>> matrix) {
        List<CreateArticleInput> all = new ArrayList<>();
        if (matrix != null) {
            for (List<CreateArticleInput> row : matrix) {
                if (row != null) all.addAll(row);
            }
        }
        return all;
    }

    @Override
    public Mono<Integer> bulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        return Mono.just(inputs(matrix).size());
    }

    @Override
    public Mono<Void> validateBulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        for (CreateArticleInput input : inputs(matrix)) {
            if ("invalid".equals(input.getTitle())) return Mono.error(new IllegalArgumentException("invalid title"));
        }
        return Mono.empty();
    }
}
