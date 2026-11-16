package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.services.BulkCreateService;
import org.springframework.stereotype.Service;

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
    public int bulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        return inputs(matrix).size();
    }

    @Override
    public void validateBulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        for (CreateArticleInput input : inputs(matrix)) {
            if ("invalid".equals(input.getTitle())) throw new IllegalArgumentException("invalid title");
        }
    }
}
