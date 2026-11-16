package dev.graphlink.server;

import graphql.GraphQLError;
import graphql.GraphqlErrorException;
import graphql.schema.DataFetchingEnvironment;
import org.springframework.graphql.execution.DataFetcherExceptionResolverAdapter;
import org.springframework.stereotype.Component;

@Component
public class GraphqlErrorResolver extends DataFetcherExceptionResolverAdapter {

    @Override
    protected GraphQLError resolveToSingleError(Throwable ex, DataFetchingEnvironment env) {
        if (!(ex instanceof GraphqlErrorException e)) return null;
        return GraphqlErrorException.newErrorException()
                .message(e.getMessage())
                .extensions(e.getExtensions())
                .path(env.getExecutionStepInfo().getPath().toList())
                .sourceLocation(env.getField().getSourceLocation())
                .build();
    }
}
