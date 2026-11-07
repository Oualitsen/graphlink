package dev.graphlink.server;

import graphql.language.ArrayValue;
import graphql.language.BooleanValue;
import graphql.language.FloatValue;
import graphql.language.IntValue;
import graphql.language.NullValue;
import graphql.language.ObjectField;
import graphql.language.ObjectValue;
import graphql.language.StringValue;
import graphql.language.Value;
import graphql.schema.Coercing;
import graphql.schema.GraphQLScalarType;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.graphql.execution.RuntimeWiringConfigurer;

@Configuration
public class ScalarsConfig {

    private static final class PassThrough implements Coercing<Object, Object> {
        @Override public Object serialize(Object v) { return v; }
        @Override public Object parseValue(Object v) { return v; }
        @Override public Object parseLiteral(Object literal) { return literal(literal); }
    }

    private static Object literal(Object node) {
        if (node instanceof StringValue s) return s.getValue();
        if (node instanceof BooleanValue b) return b.isValue();
        if (node instanceof IntValue i) return i.getValue().bitLength() < 64 ? (Object) i.getValue().longValue() : i.getValue();
        if (node instanceof FloatValue f) return f.getValue();
        if (node instanceof NullValue) return null;
        if (node instanceof ArrayValue a) {
            List<Object> out = new ArrayList<>();
            for (Value<?> v : a.getValues()) out.add(literal(v));
            return out;
        }
        if (node instanceof ObjectValue o) {
            Map<String, Object> out = new LinkedHashMap<>();
            for (ObjectField f : o.getObjectFields()) out.put(f.getName(), literal(f.getValue()));
            return out;
        }
        return node;
    }

    private static GraphQLScalarType passThrough(String name) {
        return GraphQLScalarType.newScalar().name(name).coercing(new PassThrough()).build();
    }

    @Bean
    public RuntimeWiringConfigurer customScalars() {
        return wiring -> wiring
            .scalar(passThrough("DateTime"))
            .scalar(passThrough("LocalDate"))
            .scalar(passThrough("Long"))
            .scalar(passThrough("BigDecimal"))
            .scalar(passThrough("JSON"))
            .scalar(passThrough("Opaque"));
    }
}
