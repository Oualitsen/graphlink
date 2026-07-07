package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.StatusService;
import org.springframework.stereotype.Service;

@Service
public class StatusServiceImpl implements StatusService {

    @Override
    public String status() {
        return "ok";
    }
}
