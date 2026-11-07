import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';

class DartClientAdaptersSerializer {
  final DartClientSerializer _client;
  DartClientAdaptersSerializer(this._client);

  String get _operationNameArg => _client.parser.operationNameAsParameter ? ', String operationName' : '';

  String get _postUrlExpr => _client.parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url';

  GLClassModel generateHttpAdapterFile() {
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'package:http/http.dart' as http;",
        "import 'package:http_parser/http_parser.dart';",
        if (_client.parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
        if (_client.parser.persistedQueriesUseGet) "import 'graph_link_persisted_queries.dart';",
      ],
      body: [
        _httpAdapterClass(),
        if (_client.parser.hasUploadMutations) _httpStreamedRequestClass(),
      ].join('\n\n'),
    );
  }

  String _httpAdapterClass() {
    return _client.codeGenUtils.createClass(
        className: 'GraphLinkHttpAdapter',
        statements: [
          'final String url;',
          'final Future<Map<String, String>?> Function()? headersProvider;',
          _client.codeGenUtils.createMethod(
            methodName: 'GraphLinkHttpAdapter',
            arguments: ['required this.url', 'this.headersProvider'],
          ),
          _client.codeGenUtils.createMethod(
            returnType: 'Future<String>',
            methodName: 'call',
            async: true,
            namedArguments: false,
            arguments: ['String payload$_operationNameArg'],
            statements: [
              _client.codeGenUtils.constDecl('extraHeaders', 'await headersProvider?.call()'),
              _client.codeGenUtils.constDecl("requestHeaders", _client.codeGenUtils.block([
                "'Content-Type': 'application/json',",
                'if (extraHeaders != null) ...extraHeaders,',
              ])),
              _client.codeGenUtils.constDecl('response', 'await ${_client.codeGenUtils.callExpression('http.post', [
                'Uri.parse($_postUrlExpr)',
                'body: payload',
                'headers: requestHeaders',
              ])}'),
              'return response.body;',
            ],
          ),
          if (_client.parser.persistedQueriesUseGet) _httpGetMethod(),
          if (_client.parser.hasUploadMutations) _httpMultipartMethod(),
        ],
    );
  }

  String _httpGetMethod() {
    return _client.codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'getCall',
      async: true,
      namedArguments: false,
      arguments: ['String payload$_operationNameArg'],
      statements: [
        _client.codeGenUtils.constDecl('uri', 'Uri.parse(url)'),
        _client.codeGenUtils.constDecl('response', 'await ${_client.codeGenUtils.callExpression('http.get', [
          'uri.replace(queryParameters: {...uri.queryParameters, ...GraphLinkGetRequest.queryParameters(payload)})',
          'headers: await headersProvider?.call()',
        ])}'),
        _client.codeGenUtils.ifStatement(
          condition: 'response.statusCode == 405',
          ifBlockStatements: ["throw const GraphLinkGetNotSupported('GET is not allowed');"],
        ),
        'return response.body;',
      ],
    );
  }

  String _httpMultipartMethod() {
    return _client.codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'multipartCall',
      async: true,
      namedArguments: false,
      arguments: ['Map<String, Object> parts', 'UploadProgressCallback? onProgress'],
      statements: [
        _client.codeGenUtils.constDecl('body', 'GLMultipartBody.of(parts)'),
        _client.codeGenUtils.constDecl('request', '_GLStreamedRequest(Uri.parse(url), body.withProgress(onProgress))'),
        'request.headers.addAll(await headersProvider?.call() ?? {});',
        "request.headers['content-type'] = body.contentType;",
        'request.contentLength = body.length;',
        _client.codeGenUtils.constDecl('streamed', 'await request.send()'),
        'return (await http.Response.fromStream(streamed)).body;',
      ],
    );
  }

  String _httpStreamedRequestClass() {
    return _client.codeGenUtils.createClass(
      className: '_GLStreamedRequest',
      extendsClassName: 'http.BaseRequest',
      statements: [
        'final Stream<List<int>> _stream;',
        _client.codeGenUtils.createMethod(
          methodName: '_GLStreamedRequest',
          namedArguments: false,
          arguments: ['Uri url', 'this._stream'],
          initializers: ["super('POST', url)"],
        ),
        _client.codeGenUtils.createMethod(
          override: true,
          returnType: 'http.ByteStream',
          methodName: 'finalize',
          namedArguments: false,
          arguments: [],
          statements: ['super.finalize();', 'return http.ByteStream(_stream);'],
        ),
      ],
    );
  }

  GLClassModel generateDioAdapterFile() {
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'dart:convert';",
        "import 'package:dio/dio.dart';",
        if (_client.parser.hasUploadMutations) "import 'package:http_parser/http_parser.dart';",
        if (_client.parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
        if (_client.parser.persistedQueriesUseGet) "import 'graph_link_persisted_queries.dart';",
      ],
      body: [
        _dioAdapterClass(),
        _dioHeadersInterceptorClass(),
      ].join('\n\n'),
    );
  }

  String _dioAdapterClass() {
    return _client.codeGenUtils.createClass(
      className: 'GraphLinkDioAdapter',
      statements: [
        'final String url;',
        'final Dio dio;',
        _client.codeGenUtils.createMethod(
          methodName: 'GraphLinkDioAdapter',
          arguments: [
            'required this.url',
            'Dio? dio',
            'Future<Map<String, String>?> Function()? headersProvider',
            'List<Interceptor> interceptors = const []',
            'BaseOptions? options',
          ],
          initializers: ["dio = dio ?? Dio(options ?? BaseOptions(contentType: 'application/json'))"],
          statements: [
            _client.codeGenUtils.ifStatement(
              condition: 'dio == null',
              ifBlockStatements: [
                _client.codeGenUtils.ifStatement(
                  condition: 'headersProvider != null',
                  ifBlockStatements: ['this.dio.interceptors.add(_HeadersInterceptor(headersProvider));'],
                ),
                'this.dio.interceptors.addAll(interceptors);',
              ],
            ),
          ],
        ),
        _client.codeGenUtils.createMethod(
          returnType: 'Future<String>',
          methodName: 'call',
          async: true,
          namedArguments: false,
          arguments: ['String payload$_operationNameArg'],
          statements: [
            _client.codeGenUtils.constDecl('response', 'await dio.post<dynamic>($_postUrlExpr, data: payload)'),
            _client.codeGenUtils.constDecl('data', 'response.data'),
            'return data is String ? data : jsonEncode(data);',
          ],
        ),
        if (_client.parser.persistedQueriesUseGet) _dioGetMethod(),
        if (_client.parser.hasUploadMutations) _dioMultipartMethod(),
      ],
    );
  }

  String _dioGetMethod() {
    return _client.codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'getCall',
      async: true,
      namedArguments: false,
      arguments: ['String payload$_operationNameArg'],
      statements: [
        _client.codeGenUtils.tryCatchFinally(
          tryStatements: [
            _client.codeGenUtils.constDecl('response',
                'await dio.get<dynamic>(url, queryParameters: GraphLinkGetRequest.queryParameters(payload))'),
            _client.codeGenUtils.constDecl('data', 'response.data'),
            'return data is String ? data : jsonEncode(data);',
          ],
          catchVariable: 'e',
          catchStatements: [
            _client.codeGenUtils.ifStatement(
              condition: 'e is DioException && e.response?.statusCode == 405',
              ifBlockStatements: ["throw const GraphLinkGetNotSupported('GET is not allowed');"],
            ),
            'rethrow;',
          ],
        ),
      ],
    );
  }

  String _dioMultipartMethod() {
    return _client.codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'multipartCall',
      async: true,
      namedArguments: false,
      arguments: ['Map<String, Object> parts', 'UploadProgressCallback? onProgress'],
      statements: [
        _client.codeGenUtils.constDecl('body', 'GLMultipartBody.of(parts)'),
        _client.codeGenUtils.constDecl(
            'response',
            'await ${_client.codeGenUtils.callExpression('dio.post<dynamic>', [
                  'url',
                  'data: body.withProgress(onProgress)',
                  'options: Options(contentType: body.contentType, headers: {if (body.length != null) \'Content-Length\': \'\${body.length}\'})',
                ])}'),
        _client.codeGenUtils.constDecl('data', 'response.data'),
        'return data is String ? data : jsonEncode(data);',
      ],
    );
  }

  String _dioHeadersInterceptorClass() {
    return _client.codeGenUtils.createClass(
      className: '_HeadersInterceptor',
      extendsClassName: 'Interceptor',
      statements: [
        'final Future<Map<String, String>?> Function() _headersProvider;',
        _client.codeGenUtils.createMethod(
          methodName: '_HeadersInterceptor',
          namedArguments: false,
          arguments: ['this._headersProvider'],
        ),
        _client.codeGenUtils.createMethod(
          override: true,
          returnType: 'Future<void>',
          methodName: 'onRequest',
          async: true,
          namedArguments: false,
          arguments: ['RequestOptions options', 'RequestInterceptorHandler handler'],
          statements: [
            _client.codeGenUtils.constDecl('headers', 'await _headersProvider()'),
            _client.codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: ['options.headers.addAll(headers);'],
            ),
            'handler.next(options);',
          ],
        ),
      ],
    );
  }

  GLClassModel generateRestHttpAdapterFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:typed_data';",
          "import 'package:http/http.dart' as http;",
          "import 'package:http_parser/http_parser.dart';",
          "import 'graph_link_rest.dart';",
          "import 'graph_link_uploads.dart';",
        ],
        body: dartRestHttpAdapter,
      );

  GLClassModel generateRestDioAdapterFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:typed_data';",
          "import 'package:dio/dio.dart';",
          "import 'package:http_parser/http_parser.dart';",
          "import 'graph_link_rest.dart';",
          "import 'graph_link_uploads.dart';",
        ],
        body: dartRestDioAdapter,
      );
}
