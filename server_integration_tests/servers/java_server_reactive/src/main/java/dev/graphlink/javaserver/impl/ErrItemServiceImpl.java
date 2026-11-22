package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.errors.ErrConflict;
import dev.graphlink.javaserver.generated.errors.ErrForbidden;
import dev.graphlink.javaserver.generated.errors.ErrNotFound;
import dev.graphlink.javaserver.generated.services.ErrItemService;
import dev.graphlink.javaserver.generated.types.ErrItem;

import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class ErrItemServiceImpl implements ErrItemService {

    @Override
    public Mono<ErrItem> errProbe(String id) {
        if ("missing".equals(id)) return Mono.error(new ErrNotFound(id, "Item " + id + " not found"));
        if ("forbidden".equals(id)) return Mono.error(new ErrForbidden("No access"));
        if ("boom".equals(id)) return Mono.error(new IllegalStateException("secret detail"));
        return Mono.just(ErrItem.builder().id(id).build());
    }

    @Override
    public Mono<ErrItem> errRest(String id) {
        if ("missing".equals(id)) return Mono.error(new ErrNotFound(id, "Item " + id + " not found"));
        if ("conflict".equals(id)) return Mono.error(new ErrConflict("duplicate", "Conflict"));
        if ("boom".equals(id)) return Mono.error(new IllegalStateException("secret detail"));
        return Mono.just(ErrItem.builder().id(id).build());
    }
}
