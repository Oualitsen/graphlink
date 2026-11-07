import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';

class PythonClientAdaptersSerializer {
  final PythonClientSerializer _client;
  PythonClientAdaptersSerializer(this._client);

  GLClassModel generateDefaultWebSocketAdapterFile() => _client.static(pythonDefaultWebSocketAdapter);

  GLClassModel? generateRestHttpxAdapterFile() {
    if (!_client.restViaHttp) return null;
    return const GLClassModel(
      imports: [
        'import inspect',
        'from typing import Any, AsyncIterator, Callable, Dict, Optional',
        '',
        'import httpx',
        '',
        'from .graph_link_rest import (',
        '    RestFormBody,',
        '    RestJsonBody,',
        '    RestMultipartBody,',
        '    RestRawBody,',
        '    RestRequest,',
        '    RestResponse,',
        '    rest_form_body,',
        '    rest_url,',
        ')',
        'from .graph_link_uploads import gl_counted_stream, gl_multipart_stream',
      ],
      body: pythonRestHttpxAdapter,
    );
  }

  GLClassModel generateHttpxAdapterFile() {
    final cg = _client.codeGenUtils;
    final nameParam = _client.parser.operationNameAsParameter ? ', operation_name: str' : '';
    final postUrl = _client.parser.operationNameAsParameter ? 'f"{self.url}?operationName={operation_name}"' : 'self.url';
    return GLClassModel(
      imports: [
        'import inspect',
        'from typing import Any, Awaitable, Callable, Dict, List, Optional',
        '',
        'import httpx',
        '',
        if (_client.parser.hasUploadMutations) 'from .graph_link_uploads import GLMultipartPart, GLUpload, UploadProgressCallback, gl_multipart_stream',
        if (_client.parser.persistedQueriesUseGet) 'from .graph_link_persisted_queries import GraphLinkGetNotSupported, GraphLinkGetRequest',
      ],
      body: cg.createClass(className: 'GraphLinkHttpxAdapter', statements: [
        cg.createMethod(
          methodName: '__init__',
          arguments: [
            'self',
            '*',
            'url: str',
            'headers_provider: Optional[Callable[[], Any]] = None',
            'client: Optional[httpx.AsyncClient] = None',
          ],
          returnType: 'None',
          statements: [
            'self.url = url',
            'self.headers_provider = headers_provider',
            'self.client = client if client is not None else httpx.AsyncClient()',
          ],
        ),
        '',
        cg.createMethod(
          async: true,
          methodName: '_extra_headers',
          arguments: ['self'],
          returnType: 'Dict[str, str]',
          statements: [
            cg.ifStatement(condition: 'self.headers_provider is None', ifBlockStatements: ['return {}']),
            cg.constDecl('provided', 'self.headers_provider()'),
            cg.ifStatement(condition: 'inspect.isawaitable(provided)', ifBlockStatements: ['provided = await provided']),
            'return dict(provided) if provided else {}',
          ],
        ),
        '',
        cg.createMethod(
          async: true,
          methodName: 'call',
          arguments: ['self', 'payload: str$nameParam'],
          returnType: 'str',
          statements: [
            cg.constDecl('headers', '{"Content-Type": "application/json", **await self._extra_headers()}'),
            cg.constDecl('response', 'await self.client.post($postUrl, content=payload, headers=headers)'),
            'return response.text',
          ],
        ),
        if (_client.parser.persistedQueriesUseGet) ...[
          '',
          cg.createMethod(
            async: true,
            methodName: 'get_call',
            arguments: ['self', 'payload: str$nameParam'],
            returnType: 'str',
            statements: [
              cg.constDecl(
                'response',
                'await ${cg.callExpression('self.client.get', [
                  'self.url',
                  'params=GraphLinkGetRequest.query_parameters(payload)',
                  'headers=await self._extra_headers()',
                ])}',
              ),
              cg.ifStatement(
                condition: 'response.status_code == 405',
                ifBlockStatements: ['raise GraphLinkGetNotSupported("GET is not allowed")'],
              ),
              'return response.text',
            ],
          ),
        ],
        if (_client.parser.hasUploadMutations) ...[
          '',
          cg.createMethod(
            async: true,
            methodName: 'multipart_call',
            arguments: ['self', 'parts: Dict[str, Any]', 'on_progress: Optional[UploadProgressCallback] = None'],
            returnType: 'str',
            statements: [
              cg.constDecl('multipart', 'self._multipart_parts(parts)'),
              'content_type, total, content = gl_multipart_stream(multipart, on_progress)',
              cg.constDecl('headers', '{**await self._extra_headers(), "Content-Type": content_type}'),
              cg.ifStatement(condition: 'total is not None', ifBlockStatements: ['headers["Content-Length"] = str(total)']),
              cg.constDecl('response', 'await self.client.post(self.url, content=content, headers=headers)'),
              'return response.text',
            ],
          ),
        ],
        if (_client.parser.hasUploadMutations) ...[
          '',
          cg.createMethod(
            methodName: '_multipart_parts',
            arguments: ['parts: Dict[str, Any]'],
            returnType: 'List[GLMultipartPart]',
            decorators: ['@staticmethod'],
            statements: [
              'return [GLMultipartPart(name=k, file=v) if isinstance(v, GLUpload) else GLMultipartPart(name=k, value=str(v)) for k, v in parts.items()]',
            ],
          ),
        ],
        '',
        cg.createMethod(async: true, methodName: 'aclose', arguments: ['self'], returnType: 'None', statements: ['await self.client.aclose()']),
      ]),
    );
  }
}
