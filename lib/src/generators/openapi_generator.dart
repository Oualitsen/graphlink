import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/io_utils.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_openapi_extension.dart';
import 'package:graphlink/src/serializers/openapi_constants.dart';
import 'package:graphlink/src/serializers/openapi_serializer.dart';

/// Lines are kept whole so no chunk splits an escape sequence or a surrogate pair.
/// JVM class files cap one string constant at 65535 bytes, hence the chunks.
List<String> openApiChunks(String text, {int maxLength = 8000}) {
  final chunks = <String>[];
  final current = StringBuffer();
  for (final line in text.split('\n')) {
    final withBreak = '$line\n';
    if (current.isNotEmpty && current.length + withBreak.length > maxLength) {
      chunks.add(current.toString());
      current.clear();
    }
    current.write(withBreak);
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}

class OpenApiOutput {
  final String spec;
  final String docsPage;
  final OpenApiConfig config;

  const OpenApiOutput({required this.spec, required this.docsPage, required this.config});

  bool get serve => config.serve;

  List<String> get specChunks => openApiChunks(spec);

  List<String> get docsChunks => openApiChunks(docsPage);
}

/// Null when the server has no `openapi` section or no REST operation to describe.
OpenApiOutput? buildOpenApiOutput(GLParser grammar, GeneratorConfig config) {
  final openApi = config.serverConfig?.openApi;
  if (openApi == null || grammar.restOperations.isEmpty) return null;
  final document = grammar.buildOpenApiDocument(openApi);
  return OpenApiOutput(
    spec: const OpenApiSerializer().serialize(document),
    docsPage: openApiDocsPage(title: openApi.title, specPath: openApi.specPath),
    config: openApi,
  );
}

Future<Set<String>> writeOpenApiFile(OpenApiOutput? output) async {
  final file = output?.config.file;
  if (output == null || file == null) return const {};
  final written = await saveSource(data: output.spec, path: file, plainSource: true);
  return {written.path};
}
