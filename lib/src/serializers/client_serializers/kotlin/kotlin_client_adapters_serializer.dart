import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';

class KotlinClientAdaptersSerializer {
  final KotlinClientSerializer _client;
  KotlinClientAdaptersSerializer(this._client);

  GLClassModel generateRestAdapterFile() => const GLClassModel(body: kotlinRestOkHttpAdapter);

  // ── Boilerplate file models ─────────────────────────────────────────────────

  GLClassModel generateDefaultClientAdapterFile() => GLClassModel(
        importDepencies: [
          _client.grammar.getTokenByKey('GraphLinkClientAdapter')!,
          _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: _client.grammar.hasUploadMutations
            ? kotlinDefaultGraphLinkClientAdapterWithUpload(_client.grammar.operationNameAsParameter)
            : kotlinDefaultGraphLinkClientAdapter(_client.grammar.operationNameAsParameter),
      );

  GLClassModel generateDefaultGetAdapterFile() {
    if (!_client.grammar.persistedQueriesUseGet) {
      throw StateError('The GET adapter is only generated when persistedQueriesUseGet is enabled.');
    }
    return GLClassModel(
      importDepencies: [_client.grammar.getTokenByKey('GraphLinkClientAdapter')!],
      body: kotlinDefaultGraphLinkGetAdapter(_client.grammar.operationNameAsParameter),
    );
  }

  GLClassModel generateDefaultWebSocketAdapterFile() =>
      const GLClassModel(body: kotlinDefaultGraphLinkWebSocketAdapter);
}
