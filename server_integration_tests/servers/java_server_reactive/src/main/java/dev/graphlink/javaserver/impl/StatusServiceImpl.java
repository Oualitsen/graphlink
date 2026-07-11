package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.StatusService;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class StatusServiceImpl implements StatusService {

    @Override
    public Mono<String> status() {
        return Mono.just("ok");
    }
}
