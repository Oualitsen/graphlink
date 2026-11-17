import 'package:graphlink/src/serializers/python/django_rest_serializer.dart';
import 'package:graphlink/src/serializers/python/python_ariadne_server_constants.dart';
import 'package:graphlink/src/serializers/python/python_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_rest_serializer.dart';

class DjangoAriadneServerSerializer extends PythonAriadneServerSerializer {
  DjangoAriadneServerSerializer(super.grammar, super.py, super.config);

  @override
  late final PythonRestSerializer rest = DjangoRestSerializer(grammar, py, config);

  @override
  List<String> get frameworkImports => [
        ...graphqlImports,
        if (!grammar.restOnly) ...[
          'from django.urls import path',
          'from .$ariadneRuntimeDir.graph_link_view import build_graphql_view',
          'from .$ariadneRuntimeDir.graph_link_websocket import GraphLinkWebSocketRouter',
        ],
        if (hasRest) 'from .rest.urls import build_rest_urlpatterns',
      ];

  @override
  String serializeCreateApp(String graphqlPath) {
    final restOnly = grammar.restOnly;
    final routePath = py.pythonStringLiteral(config.graphqlPath.replaceFirst(RegExp(r'^/'), ''));
    final urlpatterns = cg.createMethod(
      methodName: 'create_urlpatterns',
      arguments: ['services: GraphLinkServices'],
      returnType: 'List[Any]',
      statements: [
        ...serializeCreateAppPrelude(graphqlApp: false),
        cg.constDecl('patterns', '[]', type: 'List[Any]'),
        if (!restOnly)
          cg.constDecl(
            'view',
            cg.callExpression('build_graphql_view', [
              'schema',
              'lambda request: create_context(services, request)',
              '[max_depth_rule(max_depth)]',
              'format_error',
            ]),
          ),
        if (!restOnly) 'patterns.append(path($routePath, view))',
        if (hasRest)
          'patterns.extend(build_rest_urlpatterns(services, lambda request: create_context(services, request)))',
        'return patterns',
      ],
    );
    final createApp = cg.createMethod(
      methodName: 'create_app',
      arguments: ['services: GraphLinkServices', 'django_app: Any'],
      returnType: 'Any',
      statements: restOnly
          ? ['return django_app']
          : [
              ...serializeCreateAppPrelude(),
              'return GraphLinkWebSocketRouter(django_app, $graphqlPath, graphql_app)',
            ],
    );
    return '$urlpatterns\n\n\n$createApp';
  }
}
