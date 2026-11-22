package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.errors.ErrConflict;
import dev.graphlink.javaserver.generated.errors.ErrForbidden;
import dev.graphlink.javaserver.generated.errors.ErrNotFound;
import dev.graphlink.javaserver.generated.services.ErrItemService;
import dev.graphlink.javaserver.generated.types.ErrItem;

import org.springframework.stereotype.Service;

@Service
public class ErrItemServiceImpl implements ErrItemService {

    @Override
    public ErrItem errProbe(String id) {
        if ("missing".equals(id)) throw new ErrNotFound(id, "Item " + id + " not found");
        if ("forbidden".equals(id)) throw new ErrForbidden("No access");
        if ("boom".equals(id)) throw new IllegalStateException("secret detail");
        return ErrItem.builder().id(id).build();
    }

    @Override
    public ErrItem errRest(String id) {
        if ("missing".equals(id)) throw new ErrNotFound(id, "Item " + id + " not found");
        if ("conflict".equals(id)) throw new ErrConflict("duplicate", "Conflict");
        if ("boom".equals(id)) throw new IllegalStateException("secret detail");
        return ErrItem.builder().id(id).build();
    }
}
