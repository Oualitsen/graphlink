package dev.graphlink.server.controller;

import graphql.schema.DataFetchingEnvironment;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class LiteralsController {

    @QueryMapping
    public Map<String, Object> echoNastyArgs(DataFetchingEnvironment env) {
        return env.getArguments();
    }

    @QueryMapping
    public Object echoNasty(DataFetchingEnvironment env) {
        return env.getArgument("input");
    }

    @QueryMapping
    public Object echoInner(DataFetchingEnvironment env) {
        return env.getArgument("inner");
    }

    @QueryMapping
    public Object echoEverything(DataFetchingEnvironment env) {
        return env.getArgument("input");
    }

    @QueryMapping
    public Map<String, Object> treeStats(DataFetchingEnvironment env) {
        List<Integer> flat = new ArrayList<>();
        int depth = walk(env.getArgument("tree"), flat);
        Map<String, Object> out = new HashMap<>();
        out.put("flat", flat);
        out.put("depth", depth);
        return out;
    }

    @SuppressWarnings("unchecked")
    private int walk(Map<String, Object> node, List<Integer> flat) {
        flat.add((Integer) node.get("value"));
        List<Map<String, Object>> children = (List<Map<String, Object>>) node.get("children");
        int deepest = 0;
        if (children != null) {
            for (Map<String, Object> child : children) {
                deepest = Math.max(deepest, walk(child, flat));
            }
        }
        return deepest + 1;
    }

    @QueryMapping
    public int pingLength(DataFetchingEnvironment env) {
        return chain(env.getArgument("ping"), "pong", "ping");
    }

    @SuppressWarnings("unchecked")
    private int chain(Map<String, Object> node, String next, String after) {
        int count = 0;
        String key = next;
        while (node != null) {
            count++;
            node = (Map<String, Object>) node.get(key);
            key = key.equals(next) ? after : next;
        }
        return count;
    }

    @QueryMapping
    public String describePet(DataFetchingEnvironment env) {
        Map<String, Object> pet = env.getArgument("pet");
        if (pet.containsKey("cat")) {
            return "cat:" + pet.get("cat");
        }
        return "dog:" + pet.get("dog");
    }

    @QueryMapping
    public Map<String, Object> legacy(DataFetchingEnvironment env) {
        Map<String, Object> out = new HashMap<>();
        out.put("id", "l1");
        out.put("old", env.getArgument("withReason"));
        out.put("older", env.getArgument("plain"));
        out.put("mood", "CALM");
        return out;
    }

    @QueryMapping
    public Map<String, Object> shelf() {
        return Map.of("id", "s1");
    }

    @org.springframework.graphql.data.method.annotation.SchemaMapping(typeName = "Shelf", field = "items")
    public List<String> shelfItems(DataFetchingEnvironment env) {
        return List.of(
            "tags=" + env.getArgument("tags"),
            "kind=" + env.getArgument("kind"),
            "filter=" + env.getArgument("filter"),
            "limit=" + env.getArgument("limit"));
    }
}
