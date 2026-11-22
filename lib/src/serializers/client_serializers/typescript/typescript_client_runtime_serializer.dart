import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_vars.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';

class TypeScriptClientRuntimeSerializer {
  final TypeScriptClientSerializer _client;
  TypeScriptClientRuntimeSerializer(this._client);

  GLClassModel generateCacheStoreFile() =>
      const GLClassModel(body: tsCacheStore);

  GLClassModel generateInMemoryCacheStoreFile() => const GLClassModel(
        imports: [
          "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
        ],
        body: tsInMemoryCacheStore,
      );

  GLClassModel generateCacheEntryFile() =>
      const GLClassModel(body: tsCacheEntry);

  GLClassModel generateTagEntryFile() =>
      const GLClassModel(body: tsTagEntry);

  GLClassModel generateJsonChecksFile() =>
      const GLClassModel(body: tsJsonChecks);

  GLClassModel generateDomainErrorFile() => const GLClassModel(body: tsDomainError);

  GLClassModel generateLockFile() =>
      const GLClassModel(body: tsLock);

  GLClassModel generatePartialQueryFile() =>
      const GLClassModel(body: tsPartialQuery);

  GLClassModel generateWsAdapterFile() =>
      const GLClassModel(body: tsWsAdapter);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: tsWsMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() {
    final payloadToken = _client.parser.getTypeByName('GraphLinkPayload');
    final payloadImport = payloadToken != null
        ? _client.serializer.serializeImportToken(payloadToken)
        : '';
    return GLClassModel(
      imports: [
        if (payloadImport.isNotEmpty) payloadImport,
        "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
        "import { _GL_WS } from './graph-link-ws-message-types.js';",
        "import type { _GlWsMsg } from './graph-link-ws-message-types.js';",
      ],
      body: tsSubscriptionHandler,
    );
  }

  GLClassModel generateSha256File() {
    if (!_client.parser.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(body: tsSha256);
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!_client.parser.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      body: _client.parser.persistedQueriesUseGet ? '$tsPersistedQueries\n$tsPersistedQueriesGet' : tsPersistedQueries,
    );
  }

  GLClassModel generateResolverBaseFile() {
    final payloadToken = _client.parser.getTypeByName('GraphLinkPayload');
    final payloadImport = payloadToken != null
        ? _client.serializer.serializeImportToken(payloadToken)
        : '';
    return GLClassModel(
      imports: [
        if (payloadImport.isNotEmpty) payloadImport,
        "import type { $adapterType } from './graph-link-adapter.js';",
        "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
        "import type { GraphLinkError } from '../types/graph-link-error.js';",
        "import { GraphLinkCacheEntry } from './graph-link-cache-entry.js';",
        "import { GraphLinkTagEntry, __GL_TAG_KEY_PREFIX__ } from './graph-link-tag-entry.js';",
        "import type { GraphLinkPartialQuery } from './graph-link-partial-query.js';",
        "import { GraphLinkLock } from './graph-link-lock.js';",
        if (_client.parser.persistedQueries) ...[
          "import { GraphLinkSha256 } from './graph-link-sha256.js';",
          if (_client.parser.persistedQueriesUseGet)
            "import { GraphLinkPersistedQueries, GraphLinkGetNotSupported } from './graph-link-persisted-queries.js';"
          else
            "import { GraphLinkPersistedQueries } from './graph-link-persisted-queries.js';",
        ],
      ],
      body: resolverBase(),
    );
  }

  GLClassModel generateRestFile() => const GLClassModel(
        imports: [
          "import { glUploadProgress, glUploadStream } from './graph-link-uploads.js';",
          "import type { GLUpload, UploadProgressCallback } from './graph-link-uploads.js';",
        ],
        body: tsRestFile,
      );

  GLClassModel generateRestResolverFile() => const GLClassModel(
        imports: [
          "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
          "import { GraphLinkCacheEntry } from './graph-link-cache-entry.js';",
          "import { GraphLinkPartialQuery } from './graph-link-partial-query.js';",
          "import { GLDownload, RestError, restNavigate } from './graph-link-rest.js';",
          "import type { DownloadProgressCallback, GLRestAdapter, RestRequest, RestResponse } from './graph-link-rest.js';",
        ],
        body: tsRestResolver,
      );

  // ── Resolver base class ───────────────────────────────────────────────────

  String get _tagKeyDecl =>
      _client.cg.constDecl('tagKey', r'`${__GL_TAG_KEY_PREFIX__}${tag}`');

  List<String> get _addKeyStatements => [
        _client.cg.constDecl('data', 'await this.$svStore.get(tagKey)'),
        _client.cg.constDecl(
          'entry',
          _client.cg.ternaryOp(
            condition: 'data !== null',
            positiveStatement: 'GraphLinkTagEntry.decode(data)',
            negativeStatement: 'new GraphLinkTagEntry(new Set())',
          ),
        ),
        'entry.add(key);',
        'await this.$svStore.set(tagKey, entry.encode());',
      ];

  String _synchronized(List<String> statements) =>
      'await lock.synchronized(async () => ${_client.cg.block(statements)});';

  String resolverBase() {
    return _client.cg.createClass(
      className: 'GraphLinkResolverBase',
      exported: true,
      statements: [
        'protected readonly ${svStore}: $cacheStoreType;',
        'protected readonly ${svTagLocks}: Map<string, GraphLinkLock>;',
        'protected readonly ${svFragMap}: Record<string, string>;',
        'protected readonly ${svAdapter}?: $adapterType;',
        if (_client.parser.persistedQueries) ...[
          'protected readonly ${svHashes}: Map<string, string> = new Map();',
          'protected ${svPersistedUnsupported} = false;',
        ],
        if (_client.parser.persistedQueriesUseGet) ...[
          'protected readonly ${svGetAdapter}?: $adapterType;',
          'protected ${svGetUnsupported} = false;',
        ],
        _client.cg.createMethod(
          methodName: 'constructor',
          arguments: [
            'store: $cacheStoreType',
            'tagLocks: Map<string, GraphLinkLock>',
            'fragMap: Record<string, string>',
            'adapter?: $adapterType',
            if (_client.parser.persistedQueriesUseGet) 'getAdapter?: $adapterType',
          ],
          statements: [
            'this.$svStore = store;',
            'this.$svTagLocks = tagLocks;',
            'this.$svFragMap = fragMap;',
            'this.$svAdapter = adapter;',
            if (_client.parser.persistedQueriesUseGet) 'this.$svGetAdapter = getAdapter;',
          ],
        ),
        if (_client.parser.persistedQueries) ...[
          _glHashMethod(),
          _glSendMethod(),
          if (_client.parser.persistedQueriesUseGet) _glSendHashOnlyMethod(),
        ],
        _client.cg.createMethod(
          methodName: '_glCallAdapter',
          async: true,
          returnType: 'string',
          arguments: ['payload: GraphLinkPayload'],
          statements: _client.parser.persistedQueries
              ? _persistedCallAdapterStatements()
              : [
                  if (_client.parser.operationNameAsParameter)
                    'return await this.$svAdapter!(JSON.stringify(payload), payload.operationName);'
                  else
                    'return await this.$svAdapter!(JSON.stringify(payload));'
                ],
        ),
        _client.cg.createMethod(
          methodName: '_executeFull<T>',
          async: true,
          returnType: 'T',
          arguments: [
            'query: string',
            'fragmentNames: string[]',
            'operationName: string',
            'variables: Record<string, unknown>',
          ],
          statements: [
            _client.cg.constDecl('fullQuery', 'this.assembleQuery(query, fragmentNames)'),
            _client.cg.constDecl('payload', '{ query: fullQuery, operationName, variables }', type: 'GraphLinkPayload'),
            _client.cg.constDecl('response', 'await this._glCallAdapter(payload)'),
            _client.cg.constDecl('json', 'JSON.parse(response)'),
            _client.cg.ifStatement(
              condition:
                  "json === null || typeof json !== 'object' || Array.isArray(json) || ((json.data === null || typeof json.data !== 'object') && !(Array.isArray(json.errors) && json.errors.length > 0))",
              ifBlockStatements: [
                "const error: GraphLinkError = { message: 'GraphQL response has no data', path: null, extensions: null, locations: null, status: null, body: response };",
                'throw [error];',
              ],
            ),
            _client.cg.ifStatement(
              condition: 'Array.isArray(json.errors) && json.errors.length === 0',
              ifBlockStatements: ['json.errors = null;'],
            ),
            'return json as T;',
          ],
        ),
        _client.cg.createMethod(
          methodName: '_getFromCache',
          async: true,
          arguments: [
            'key: string',
            'tags: string[]',
            'staleIfOffline: boolean',
          ],
          returnType: 'GraphLinkCacheEntry | null',
          statements: [
            _client.cg.constDecl('result', 'await this.$svStore.get(key)'),
            _client.cg.ifStatement(
              condition: 'result !== null',
              ifBlockStatements: [
                _client.cg.constDecl('entry', 'GraphLinkCacheEntry.fromJson(JSON.parse(result))'),
                _client.cg.ifStatement(
                  condition: 'entry.isExpired',
                  ifBlockStatements: [
                    _client.cg.ifStatement(
                      condition: 'staleIfOffline',
                      ifBlockStatements: ['return entry.asStale();'],
                    ),
                    'void this.$svStore.invalidate(key);',
                    _client.cg.ifStatement(
                      condition: 'tags.length > 0',
                      ifBlockStatements: ['void this._removeKeyFromTags(key, tags);'],
                    ),
                    'return null;',
                  ],
                  elseBlockStatements: ['return entry;'],
                ),
              ],
            ),
            'return null;',
          ],
        ),
        _client.cg.createMethod(
          methodName: 'protected _glEpoch',
          arguments: ['tags: string[]'],
          returnType: 'number',
          statements: [
            "let epoch = this.$svTagLocks.get('\\u0000all')?.epoch ?? 0;",
            _client.cg.forEachLoop(
              variable: 'tag',
              iterable: 'tags',
              statements: ['epoch += this.$svTagLocks.get(tag)?.epoch ?? 0;'],
            ),
            'return epoch;',
          ],
        ),
        _client.cg.createMethod(
          methodName: 'protected _glEpochs',
          arguments: ['queries: GraphLinkPartialQuery[]'],
          returnType: 'number[]',
          statements: ['return queries.map(q => this._glEpoch(q.tags));'],
        ),
        _client.cg.createMethod(
          methodName: 'protected _glCallCached',
          arguments: [
            'payload: GraphLinkPayload',
            'queries: GraphLinkPartialQuery[]',
            'epochs: number[]',
          ],
          returnType: 'Promise<string>',
          statements: [
            _client.cg.ifStatement(
              condition: 'queries.some(q => q.ttl <= 0 || !q.cacheKey)',
              ifBlockStatements: ['return this._glCallAdapter(payload);'],
            ),
            r"const key = `\u0000flight|${payload.operationName}|${queries.map(q => q.cacheKey).sort().join(',')}|${epochs.reduce((a, b) => a + b, 0)}`;",
            'return this._glFlight(key, () => this._glCallAdapter(payload));',
          ],
        ),
        _client.cg.createMethod(
          methodName: 'protected _glFlight<T>',
          arguments: ['key: string', 'send: () => Promise<T>'],
          returnType: 'Promise<T>',
          statements: [
            'let lock = this.$svTagLocks.get(key);',
            _client.cg.ifStatement(
              condition: '!lock',
              ifBlockStatements: [
                'lock = new GraphLinkLock();',
                'this.$svTagLocks.set(key, lock);',
              ],
            ),
            _client.cg.ifStatement(
              condition: 'lock.flight',
              ifBlockStatements: ['return lock.flight as Promise<T>;'],
            ),
            'const flightLock = lock;',
            'const started = send().finally(() => ${_client.cg.block([
                  'flightLock.flight = undefined;',
                  'this.$svTagLocks.delete(key);',
                ])});',
            'flightLock.flight = started;',
            'return started;',
          ],
        ),
        _client.cg.createMethod(
          methodName: '_invalidateAllEntries',
          async: true,
          arguments: [],
          returnType: 'void',
          statements: [
            "let lock = this.$svTagLocks.get('\\u0000all');",
            _client.cg.ifStatement(
              condition: '!lock',
              ifBlockStatements: [
                'lock = new GraphLinkLock();',
                "this.$svTagLocks.set('\\u0000all', lock);",
              ],
            ),
            'lock.epoch++;',
            'await lock.synchronized(() => this.$svStore.invalidateAll());',
          ],
        ),
        _client.cg.createMethod(
          methodName: '_invalidateByTags',
          async: true,
          arguments: ['tags: string[]'],
          returnType: 'void',
          statements: [
            _client.cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              _tagKeyDecl,
              _client.cg.constDecl('lock', 'this.$svTagLocks.get(tag)!'),
              'lock.epoch++;',
              _synchronized([
                _client.cg.constDecl('data', 'await this.$svStore.get(tagKey)'),
                _client.cg.ifStatement(
                  condition: 'data !== null',
                  ifBlockStatements: [
                    _client.cg.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
                    _client.cg.forEachLoop(
                      variable: 'k',
                      iterable: 'entry.keys',
                      statements: ['await this.$svStore.invalidate(k);'],
                    ),
                    'await this.$svStore.invalidate(tagKey);',
                  ],
                ),
              ]),
            ]),
          ],
        ),
        _client.cg.createMethod(
          methodName: '_addKeyToTags',
          async: true,
          arguments: ['key: string', 'tags: string[]'],
          returnType: 'void',
          statements: [
            _client.cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              _tagKeyDecl,
              _client.cg.constDecl('lock', 'this.$svTagLocks.get(tag)!'),
              _synchronized(_addKeyStatements),
            ]),
          ],
        ),
        _client.cg.createMethod(
          methodName: 'protected async _glStoreIfCurrent',
          arguments: ['key: string', 'value: string', 'tags: string[]', 'epoch: number'],
          returnType: 'Promise<void>',
          statements: [
            _client.cg.constDecl('names', "Array.from(new Set(['\\u0000all', ...tags])).sort()"),
            'const run = async (i: number): Promise<void> => ${_client.cg.block([
              _client.cg.ifStatement(condition: 'i < names.length', ifBlockStatements: [
                'let lock = this.$svTagLocks.get(names[i]!);',
                _client.cg.ifStatement(condition: '!lock', ifBlockStatements: [
                  'lock = new GraphLinkLock();',
                  'this.$svTagLocks.set(names[i]!, lock);',
                ]),
                'await lock.synchronized(() => run(i + 1));',
                'return;',
              ]),
              _client.cg.ifStatement(condition: 'this._glEpoch(tags) !== epoch', ifBlockStatements: ['return;']),
              'await this.$svStore.set(key, value);',
              _client.cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
                _tagKeyDecl,
                ..._addKeyStatements,
              ]),
            ])};',
            'await run(0);',
          ],
        ),
        _client.cg.createMethod(
          methodName: '_removeKeyFromTags',
          async: true,
          arguments: ['key: string', 'tags: string[]'],
          returnType: 'void',
          statements: [
            _client.cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              _tagKeyDecl,
              _client.cg.constDecl('lock', 'this.$svTagLocks.get(tag) ?? (() => { const l = new GraphLinkLock(); this.$svTagLocks.set(tag, l); return l; })()'),
              _synchronized([
                _client.cg.constDecl('data', 'await this.$svStore.get(tagKey)'),
                _client.cg.ifStatement(
                  condition: 'data !== null',
                  ifBlockStatements: [
                    _client.cg.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
                    'entry.remove(key);',
                    _client.cg.ifStatement(
                      condition: 'entry.keys.size === 0',
                      ifBlockStatements: ['await this.$svStore.invalidate(tagKey);'],
                      elseBlockStatements: ['await this.$svStore.set(tagKey, entry.encode());'],
                    ),
                  ],
                ),
              ]),
            ]),
          ],
        ),
        _client.cg.createMethod(
          methodName: 'assembleQuery',
          returnType: 'string',
          arguments: ['query: string', 'fragmentNames: string[]'],
          statements: [
            'let result = query;',
            _client.cg.forEachLoop(
              variable: 'name',
              iterable: 'fragmentNames',
              statements: [
                _client.cg.constDecl('frag', 'this.$svFragMap[name]'),
                _client.cg.ifStatement(
                  condition: 'frag',
                  ifBlockStatements: ["result += '\\n' + frag;"],
                ),
              ],
            ),
            'return result;',
          ],
        ),
      ],
    );
  }

  String _glHashMethod() {
    return _client.cg.createMethod(
      methodName: 'glHash',
      returnType: 'string',
      arguments: ['query: string'],
      statements: [
        _client.cg.constDecl('cached', 'this.$svHashes.get(query)'),
        _client.cg.ifStatement(
          condition: 'cached !== undefined',
          ifBlockStatements: ['return cached;'],
        ),
        _client.cg.constDecl('hash', 'GraphLinkSha256.hex(query)'),
        'this.$svHashes.set(query, hash);',
        'return hash;',
      ],
    );
  }

  String _glSendMethod() {
    final call = _client.parser.operationNameAsParameter
        ? 'this.$svAdapter!(JSON.stringify(body), body.operationName as string)'
        : 'this.$svAdapter!(JSON.stringify(body))';
    return _client.cg.createMethod(
      methodName: '_glSend',
      async: true,
      returnType: 'string',
      arguments: ['body: Record<string, unknown>'],
      statements: ['return await $call;'],
    );
  }

  String _glSendHashOnlyMethod() {
    final call = _client.parser.operationNameAsParameter
        ? 'this.$svGetAdapter!(JSON.stringify(body), body.operationName as string)'
        : 'this.$svGetAdapter!(JSON.stringify(body))';
    return _client.cg.createMethod(
      methodName: '_glSendHashOnly',
      async: true,
      returnType: 'string',
      arguments: ['payload: GraphLinkPayload', 'body: Record<string, unknown>'],
      statements: [
        _client.cg.ifStatement(
          condition: "this.$svGetUnsupported || payload.query.startsWith('mutation')",
          ifBlockStatements: ['return await this._glSend(body);'],
        ),
        _client.cg.tryCatchFinally(
          tryStatements: ['return await $call;'],
          catchVariable: 'e',
          catchStatements: [
            _client.cg.ifStatement(
              condition: '!(e instanceof GraphLinkGetNotSupported)',
              ifBlockStatements: ['throw e;'],
            ),
            'this.$svGetUnsupported = true;',
            'return await this._glSend(body);',
          ],
        ),
      ],
    );
  }

  List<String> _persistedCallAdapterStatements() {
    return [
      _client.cg.ifStatement(
        condition:
            'this.$svPersistedUnsupported || payload.query.length <= GraphLinkPersistedQueries.minQueryLength',
        ifBlockStatements: ['return await this._glSend({ ...payload });'],
      ),
      _client.cg.constDecl('extensions', 'GraphLinkPersistedQueries.extensions(this.glHash(payload.query))'),
      _client.cg.constDecl('hashOnly',
          '{ operationName: payload.operationName, variables: payload.variables, extensions }'),
      _client.cg.constDecl(
        'response',
        _client.parser.persistedQueriesUseGet
            ? 'await this._glSendHashOnly(payload, hashOnly)'
            : 'await this._glSend(hashOnly)',
      ),
      _client.cg.constDecl('failure', 'GraphLinkPersistedQueries.failure(response)'),
      _client.cg.ifStatement(condition: 'failure === null', ifBlockStatements: ['return response;']),
      _client.cg.constDecl('body', '{ ...payload }', type: 'Record<string, unknown>'),
      _client.cg.ifStatement(
        condition: 'failure === GraphLinkPersistedQueries.notSupported',
        ifBlockStatements: ['this.$svPersistedUnsupported = true;'],
        elseBlockStatements: ['body.extensions = extensions;'],
      ),
      'return await this._glSend(body);',
    ];
  }
}
