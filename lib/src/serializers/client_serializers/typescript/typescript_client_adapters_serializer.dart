import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_rest_constants.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';

class TypeScriptClientAdaptersSerializer {
  final TypeScriptClientSerializer _client;
  TypeScriptClientAdaptersSerializer(this._client);

  GLClassModel generateAdapterTypeFile() =>
      GLClassModel(body: _client.adapterTypeAlias());

  // ── Monolithic single-file generator (kept for test backward-compatibility) ──

  GLClassModel generateDefaultWsAdapterFile() => const GLClassModel(
        imports: [
          "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
          "import { _makeChannel, _makeBroadcastChannel } from './graph-link-subscription-handler.js';",
        ],
        body: tsDefaultWsAdapter,
      );

  GLClassModel? generateAdaptersFile(TypeScriptHttpAdapter httpAdapter) {
    if (httpAdapter == TypeScriptHttpAdapter.none) return null;
    final hasUploads = _client.parser.hasUploadMutations;
    final buffer = StringBuffer();
    buffer.writeln(
      "import type { $adapterType } from './graph-link-adapter.js';",
    );
    buffer.writeln("import type { GraphLinkError } from '../types/graph-link-error.js';");
    if (hasUploads && httpAdapter == TypeScriptHttpAdapter.fetch) {
      buffer.writeln(
        "import { glFetchMultipart } from './graph-link-uploads.js';",
      );
      buffer.writeln(
        "import type { GLUpload, GLMultipartAdapter, GLMultipartPart, UploadProgressCallback } from './graph-link-uploads.js';",
      );
    }
    if (_client.parser.persistedQueriesUseGet) {
      buffer.writeln(
        "import { GraphLinkGetNotSupported, GraphLinkGetRequest } from './graph-link-persisted-queries.js';",
      );
    }
    buffer.writeln();
    buffer.writeln(tsCheckHttpStatus);
    if (httpAdapter == TypeScriptHttpAdapter.fetch) {
      buffer.writeln(tsFetchAdapter(_client.parser.operationNameAsParameter));
      if (_client.parser.persistedQueriesUseGet) buffer.writeln(tsFetchGetAdapter(_client.parser.operationNameAsParameter));
      if (hasUploads) buffer.writeln(tsMultipartFetchAdapter);
    }
    if (httpAdapter == TypeScriptHttpAdapter.axios) {
      buffer.writeln(tsAxiosAdapter(_client.parser.operationNameAsParameter));
      if (_client.parser.persistedQueriesUseGet) buffer.writeln(tsAxiosGetAdapter(_client.parser.operationNameAsParameter));
    }
    return GLClassModel(body: buffer.toString());
  }

  // ── REST files ────────────────────────────────────────────────────────────

  GLClassModel? generateRestAdaptersFile() {
    if (!_client.hasRest || _client.restHttpAdapter == TypeScriptHttpAdapter.none) return null;
    final fetch = _client.restHttpAdapter == TypeScriptHttpAdapter.fetch;
    return GLClassModel(
      imports: [
        "import { RestResponse, restFormBody, restUrl${fetch ? ', restCountedStream' : ''} } from './graph-link-rest.js';",
        "import { ${fetch ? 'glFetchMultipart' : 'glFormDataMultipart, glMultipartBody, glUploadProgress, glUploadStream'} } from './graph-link-uploads.js';",
        "import type { GLRestAdapter, RestRequest } from './graph-link-rest.js';",
      ],
      body: fetch ? tsRestFetchAdapter : tsRestAxiosAdapter,
    );
  }

  // ── Uploads file ──────────────────────────────────────────────────────────
}
