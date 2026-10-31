package dev.graphlink.uploadserver.controller;

import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class QueryController {

    @QueryMapping
    public boolean ping() {
        return true;
    }
}
