package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.DeleteArticleService;
import org.springframework.stereotype.Service;

@Service
public class DeleteArticleServiceImpl implements DeleteArticleService {

    @Override
    public Boolean deleteArticle(String id) {
        return Data.articles.removeIf(a -> a.getId().equals(id));
    }
}
