package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.AuthorService;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

@Service
public class AuthorServiceImpl implements AuthorService {

    @Override
    public Author getAuthor(String id) {
        return Data.authors.stream().filter(a -> a.getId().equals(id)).findFirst().orElse(null);
    }

    @Override
    public List<Author> listAuthors() {
        return new ArrayList<>(Data.authors);
    }
}
