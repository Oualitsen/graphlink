package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.AuthorService;
import dev.graphlink.javaserver.generated.types.Author;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Service
public class AuthorServiceImpl implements AuthorService {

    @Override
    public Mono<Author> getAuthor(String id) {
        return Mono.justOrEmpty(Data.authors.stream().filter(a -> a.getId().equals(id)).findFirst());
    }

    @Override
    public Flux<Author> listAuthors() {
        return Flux.fromIterable(Data.authors);
    }
}
