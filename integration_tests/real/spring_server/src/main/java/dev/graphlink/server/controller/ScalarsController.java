package dev.graphlink.server.controller;

import graphql.schema.DataFetchingEnvironment;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class ScalarsController {

    @QueryMapping
    public Map<String, Object> scalarFixture() {
        Map<String, Object> json = new LinkedHashMap<>();
        json.put("name", "x");
        json.put("n", 1);
        json.put("list", List.of(1, "two", false));
        Map<String, Object> bag = new LinkedHashMap<>();
        bag.put("dt", "2026-01-02T03:04:05Z");
        bag.put("date", "2026-01-02");
        bag.put("long", 9007199254740993L);
        bag.put("big", new BigDecimal("12345678901234567890.123456789"));
        bag.put("json", json);
        bag.put("opaque", "o-1");
        bag.put("dts", List.of("2026-01-02T03:04:05Z", "2027-02-03T04:05:06Z"));
        bag.put("longs", java.util.Arrays.asList(1L, null, 9223372036854775807L));
        return bag;
    }

    @QueryMapping
    public Object echoScalars(DataFetchingEnvironment env) {
        return env.getArgument("input");
    }

    @QueryMapping
    public Map<String, Object> echoScalarArgs(DataFetchingEnvironment env) {
        return env.getArguments();
    }
}
