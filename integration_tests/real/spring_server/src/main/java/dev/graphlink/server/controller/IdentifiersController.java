package dev.graphlink.server.controller;

import graphql.schema.DataFetchingEnvironment;
import java.util.List;
import java.util.Map;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class IdentifiersController {

    @QueryMapping
    public Map<String, Object> reservedEcho(DataFetchingEnvironment env) {
        return env.getArguments();
    }

    @QueryMapping
    public Object reservedEchoInput(DataFetchingEnvironment env) {
        return env.getArgument("input");
    }

    @QueryMapping
    public String literalEcho(DataFetchingEnvironment env) {
        return env.getArgument("v");
    }

    @QueryMapping
    public List<String> literals() {
        return List.of("default", "class", "None", "True", "nil", "undefined", "NaN", "self");
    }

    @QueryMapping
    public Map<String, Object> clashes() {
        Map<String, Object> out = new java.util.HashMap<>();
        for (String k : List.of("error", "response", "request", "list", "map", "object", "optional", "date", "result", "void")) {
            out.put(k, Map.of("id", k + "-1"));
        }
        return out;
    }

    @QueryMapping
    public Object oddEcho(DataFetchingEnvironment env) {
        return env.getArgument("input");
    }

    @QueryMapping(name = "import")
    public String importOp(DataFetchingEnvironment env) { return env.getArgument("value"); }

    @QueryMapping(name = "default")
    public String defaultOp(DataFetchingEnvironment env) { return env.getArgument("value"); }

    @QueryMapping(name = "new")
    public String newOp(DataFetchingEnvironment env) { return env.getArgument("value"); }

    @QueryMapping(name = "func")
    public String funcOp(DataFetchingEnvironment env) { return env.getArgument("value"); }

    @QueryMapping(name = "None")
    public String noneOp(DataFetchingEnvironment env) { return env.getArgument("value"); }

    @QueryMapping(name = "self")
    public String selfOp(DataFetchingEnvironment env) { return env.getArgument("value"); }
}
