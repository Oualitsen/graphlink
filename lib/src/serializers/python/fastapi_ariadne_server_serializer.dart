import 'package:graphlink/src/serializers/python/fastapi_rest_serializer.dart';
import 'package:graphlink/src/serializers/python/python_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_rest_serializer.dart';

class FastapiAriadneServerSerializer extends PythonAriadneServerSerializer {
  FastapiAriadneServerSerializer(super.grammar, super.py, super.config);

  @override
  late final PythonRestSerializer rest = FastapiRestSerializer(grammar, py, config);

  @override
  List<String> get frameworkImports => [
        'from fastapi import FastAPI',
        'from fastapi.middleware.cors import CORSMiddleware',
        ...graphqlImports,
        if (!grammar.restOnly) 'from starlette.routing import Route, WebSocketRoute',
        if (hasRest) 'from .rest.router import build_rest_router',
      ];

  @override
  String serializeCreateApp(String graphqlPath) {
    return cg.createMethod(
      methodName: 'create_app',
      arguments: ['services: GraphLinkServices'],
      returnType: 'FastAPI',
      statements: [
        ...serializeCreateAppPrelude(),
        cg.constDecl('app', 'FastAPI(docs_url=None, redoc_url=None, openapi_url=None)'),
        'app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])',
        if (!grammar.restOnly) ...[
          'app.router.routes.append(Route($graphqlPath, graphql_app))',
          'app.router.routes.append(WebSocketRoute($graphqlPath, graphql_app))',
        ],
        if (hasRest) 'app.include_router(build_rest_router(services, lambda request: create_context(services, request)))',
        'return app',
      ],
    );
  }
}
