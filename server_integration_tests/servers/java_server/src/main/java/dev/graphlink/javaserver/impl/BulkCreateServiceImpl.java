package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.CreateArticleInput;
import dev.graphlink.javaserver.generated.services.BulkCreateService;
import dev.graphlink.javaserver.generated.types.Article;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class BulkCreateServiceImpl implements BulkCreateService {

    @Override
    public int bulkCreate(List<? extends List<CreateArticleInput>> matrix) {
        int count = 0;
        return count;
    }

    @Override
    public void validateBulkCreate(List<? extends List<CreateArticleInput>> matrix) {

    }
}
