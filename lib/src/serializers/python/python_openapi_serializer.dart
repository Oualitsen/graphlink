import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';

const pythonOpenApiFile = 'rest/openapi.py';

class PythonOpenApiSerializer {
  final OpenApiOutput openApi;
  final PythonSerializer py;
  final _cg = PythonCodeGenUtils();

  PythonOpenApiSerializer(this.openApi, this.py);

  String _literal(String text) => py.pythonStringLiteral(text);

  String _constants() => [
        _cg.constDecl('OPENAPI_SPEC', _literal(openApi.spec), type: 'str'),
        _cg.constDecl('OPENAPI_DOCS', _literal(openApi.docsPage), type: 'str'),
      ].join('\n');

  String serializeFastapi() {
    String route(String path, String name, String content, String mediaType) => _cg.createMethod(
          methodName: name,
          returnType: 'Response',
          decorators: ['@router.get(${_literal(path)}, include_in_schema=False)'],
          statements: ['return Response($content, media_type=${_literal(mediaType)})'],
        );
    final builder = _cg.createMethod(
      methodName: 'build_openapi_router',
      returnType: 'APIRouter',
      statements: [
        _cg.constDecl('router', 'APIRouter()'),
        route(openApi.config.specPath, 'openapi_spec', 'OPENAPI_SPEC', 'application/json'),
        route(openApi.config.docsPath, 'openapi_docs', 'OPENAPI_DOCS', 'text/html'),
        'return router',
      ],
    );
    return 'from fastapi import APIRouter, Response\n\n\n${_constants()}\n\n\n$builder\n';
  }

  String serializeDjango() {
    String view(String name, String content, String mediaType) => _cg.createMethod(
          methodName: name,
          arguments: ['request: Any'],
          returnType: 'HttpResponse',
          statements: ['return HttpResponse($content, content_type=${_literal(mediaType)})'],
        );
    final builder = _cg.createMethod(
      methodName: 'build_openapi_urlpatterns',
      returnType: 'List[Any]',
      statements: [
        view('openapi_spec', 'OPENAPI_SPEC', 'application/json'),
        view('openapi_docs', 'OPENAPI_DOCS', 'text/html'),
        'return [',
        '    path(${_literal(_relative(openApi.config.specPath))}, openapi_spec),',
        '    path(${_literal(_relative(openApi.config.docsPath))}, openapi_docs),',
        ']',
      ],
    );
    return 'from typing import Any, List\n\nfrom django.http import HttpResponse\nfrom django.urls import path\n\n\n${_constants()}\n\n\n$builder\n';
  }

  String _relative(String path) => path.replaceFirst(RegExp(r'^/'), '');
}
