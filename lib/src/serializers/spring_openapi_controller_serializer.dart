import 'dart:convert';

import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';

const springOpenApiControllerName = 'GraphLinkOpenApiController';

class SpringOpenApiControllerSerializer {
  final OpenApiOutput openApi;
  final String packageName;

  SpringOpenApiControllerSerializer(this.openApi, this.packageName);

  static final _java = JavaCodeGenUtils();
  static final _kotlin = KotlinCodeGenUtils();

  List<String> get javaImports => [
        'org.springframework.web.bind.annotation.GetMapping',
        'org.springframework.web.bind.annotation.RestController',
      ];

  List<String> get kotlinImports => javaImports;

  String serializeJava() {
    final body = _java.createClass(className: springOpenApiControllerName, statements: [
      'private static final String SPEC = ${_javaText(openApi.specChunks)};',
      'private static final String DOCS = ${_javaText(openApi.docsChunks)};',
      '',
      '${_javaMapping(openApi.config.specPath, 'application/json')}\n${_java.createMethod(returnType: 'public String', methodName: 'spec', statements: ['return SPEC;'])}',
      '',
      '${_javaMapping(openApi.config.docsPath, 'text/html')}\n${_java.createMethod(returnType: 'public String', methodName: 'docs', statements: ['return DOCS;'])}',
    ]);
    return '@RestController\n$body';
  }

  String serializeKotlin() {
    final body = _kotlin.kotlinClass(name: springOpenApiControllerName, body: [
      'private val specText: String = ${_kotlinText(openApi.specChunks)}',
      'private val docsText: String = ${_kotlinText(openApi.docsChunks)}',
      '',
      '${_kotlinMapping(openApi.config.specPath, 'application/json')}\n${_kotlin.createMethod(returnType: 'String', methodName: 'spec', statements: ['return specText'])}',
      '',
      '${_kotlinMapping(openApi.config.docsPath, 'text/html')}\n${_kotlin.createMethod(returnType: 'String', methodName: 'docs', statements: ['return docsText'])}',
    ]);
    return '@RestController\n$body';
  }

  String _javaMapping(String path, String contentType) =>
      '@GetMapping(value = ${_literal(path)}, produces = ${_literal(contentType)})';

  String _kotlinMapping(String path, String contentType) =>
      '@GetMapping(value = [${_kotlinLiteral(path)}], produces = [${_kotlinLiteral(contentType)}])';

  String _javaText(List<String> chunks) =>
      _java.callExpression('String.join', [_literal(''), ...chunks.map(_literal)]);

  String _kotlinText(List<String> chunks) =>
      '${_kotlin.callExpression('listOf', chunks.map(_kotlinLiteral).toList())}.joinToString("")';

  String _literal(String text) => jsonEncode(text);

  String _kotlinLiteral(String text) => jsonEncode(text).replaceAll(r'$', r'\$');
}
