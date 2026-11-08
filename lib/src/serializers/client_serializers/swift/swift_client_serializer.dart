import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_rest_operation_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';

/// Swift's `GraphLinkResolverBase`/`GraphLinkQueries`/`Mutations`/
/// `Subscriptions` use real class inheritance
/// (`class GraphLinkQueries: GraphLinkResolverBase`) — the most direct
/// translation of Kotlin's `open class` design (see
/// `KotlinClientSerializer.generateGraphLinkResolverBaseFile`). No
/// `GLImportContainer` threading is needed: `SwiftSerializer
/// .serializeImportToken` always returns `''` (single-module output), so
/// there's nothing for per-operation rendering to add imports to.
class SwiftClientSerializer extends GLClientSerializer {
  final GLParser grammar;
  final SwiftCodeGenUtils codeGenUtils = SwiftCodeGenUtils();
  final bool withDefaultAdapters;

  final bool restViaUrlSession;

  late final SwiftClientOperationSerializer _opSer;
  late final SwiftRestOperationSerializer _restSer;

  SwiftClientSerializer(
    this.grammar,
    GLSerializer serializer, {
    this.withDefaultAdapters = true,
    this.restViaUrlSession = true,
    bool commaQueryLists = false,
    bool bracketFormNesting = false,
  }) : super(serializer, GLGraphqlSerializer(grammar, false)) {
    _opSer = SwiftClientOperationSerializer(grammar, gqlSerializer, serializer, codeGenUtils);
    _restSer = SwiftRestOperationSerializer(
      grammar,
      codeGenUtils,
      serializer as SwiftSerializer,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      grammar.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) => grammar.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get hasRest => grammar.restOperations.isNotEmpty;

  bool get hasGraphQL => GLQueryType.values.any(grammar.hasQueryType);

  bool get generatesRestAdapter => hasRest && restViaUrlSession;

  bool get usesUploadsRuntime => grammar.hasUploadMutations || hasRest;

  @override
  String renderQueryMethod(GLQueryDefinition def) => _opSer.queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) => _opSer.mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) => _opSer.mutationToMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) => _opSer.subscriptionToMethod(def);

  // ── Main client class ───────────────────────────────────────────────────────

  @override
  GLClassModel generateClient() {
    final fields = <String>[
      'private let fragmentMap: [String: String]',
      if (_hasOperations(GLQueryType.query)) 'public let queries: GraphLinkQueries',
      if (_hasOperations(GLQueryType.mutation)) 'public let mutations: GraphLinkMutations',
      if (grammar.hasSubscriptions) 'public let subscriptions: GraphLinkSubscriptions',
    ];

    final ctorParams = <String>[
      if (hasGraphQL) 'adapter: @escaping GraphLinkClientAdapter',
      if (grammar.persistedQueriesUseGet) 'getAdapter: @escaping GraphLinkClientAdapter',
      if (grammar.hasSubscriptions) 'wsAdapter: any GraphLinkWebSocketAdapter',
      if (grammar.hasUploadMutations) 'multipartAdapter: @escaping GraphLinkMultipartAdapter',
      if (hasRest) 'restAdapter: @escaping GLRestAdapter',
      'store: any GraphLinkCacheStore = InMemoryGraphLinkCacheStore()',
    ];

    final fragEntries = grammar.usedFragments
        .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
        .map((f) => '"${f.tokenInfo}": "${gqlSerializer.serializeFragmentDefinitionBase(f).escapeForSwiftStringLiteral()}"');
    final fragmentMapLiteral = fragEntries.isEmpty ? '[:]' : '[${fragEntries.join(', ')}]';
    final adapterArg = hasGraphQL ? 'adapter' : 'glNoGraphQL__';

    String restWiring(String variable, GLQueryType type) =>
        _restOperations(type).isEmpty ? '' : '\n$variable.restAdapter = restAdapter';

    final initBody = <String>[
      'self.fragmentMap = $fragmentMapLiteral',
      if (_hasOperations(GLQueryType.query))
        'let glQueries = GraphLinkQueries(adapter: $adapterArg, ${grammar.persistedQueriesUseGet ? 'getAdapter: getAdapter, ' : ''}fragmentMap: fragmentMap, store: store)${restWiring('glQueries', GLQueryType.query)}\nself.queries = glQueries',
      if (_hasOperations(GLQueryType.mutation))
        'let glMutations = GraphLinkMutations(adapter: $adapterArg${grammar.persistedQueriesUseGet ? ', getAdapter: getAdapter' : ''}${grammar.hasUploadMutations ? ', multipartAdapter: multipartAdapter' : ''}, fragmentMap: fragmentMap, store: store)${restWiring('glMutations', GLQueryType.mutation)}\nself.mutations = glMutations',
      if (grammar.hasSubscriptions)
        'self.subscriptions = GraphLinkSubscriptions(adapter: adapter, wsAdapter: wsAdapter, fragmentMap: fragmentMap, store: store)',
    ];

    final initDecl = 'public init(${ctorParams.join(', ')}) ${codeGenUtils.block(initBody)}';
    final factory = _hasFactory ? _convenienceFactories() : null;
    final classBody = [
      ...fields,
      '',
      initDecl,
      if (factory != null) ...['', factory],
    ];
    final body = 'public final class $swiftClientName ${codeGenUtils.block(classBody)}';

    return GLClassModel(imports: const ['Foundation'], body: body);
  }

  bool get _hasFactory => hasGraphQL ? withDefaultAdapters : generatesRestAdapter;

  /// Only called when [withDefaultAdapters] is true (i.e. the config's
  /// `wsAdapter` isn't `none`) — mirrors Kotlin's `hasDefaultAdapters` gate,
  /// which disables the whole `create(...)` factory (not just the
  /// subscription piece) when the user opts out of the built-in adapters.
  String _convenienceFactories() {
    final hasSubs = grammar.hasSubscriptions;
    final hasUploads = grammar.hasUploadMutations;
    final graphql = hasGraphQL;

    final params = [
      if (graphql) 'url: URL',
      if (graphql && hasSubs) 'wsUrl: URL',
      if (hasRest && restViaUrlSession) 'restBaseUrl: URL',
      if (hasRest && !restViaUrlSession) 'restAdapter: @escaping GLRestAdapter',
      'headersProvider: (@Sendable () -> [String: String])? = nil',
    ];
    final statements = [
      if (graphql)
        codeGenUtils.constDecl('httpAdapter', 'DefaultGraphLinkURLSessionAdapter(url: url, headersProvider: headersProvider)'),
      if (graphql && grammar.persistedQueriesUseGet)
        codeGenUtils.constDecl('getAdapter', 'DefaultGraphLinkURLSessionGetAdapter(url: url, headersProvider: headersProvider)'),
      if (graphql && hasSubs) codeGenUtils.constDecl('wsAdapter', 'DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: headersProvider)'),
      if (graphql && hasUploads) codeGenUtils.constDecl('multipartAdapter', 'DefaultGraphLinkURLSessionMultipartAdapter(url: url, headersProvider: headersProvider)'),
      if (hasRest && restViaUrlSession)
        codeGenUtils.constDecl('restHttpAdapter', 'DefaultGraphLinkRestAdapter(baseUrl: restBaseUrl.absoluteString, headersProvider: headersProvider)'),
      'return $swiftClientName(${[
        if (graphql) 'adapter: httpAdapter.execute',
        if (graphql && grammar.persistedQueriesUseGet) 'getAdapter: getAdapter.execute',
        if (graphql && hasSubs) 'wsAdapter: wsAdapter',
        if (graphql && hasUploads) 'multipartAdapter: multipartAdapter.executeMultipart',
        if (hasRest) restViaUrlSession ? 'restAdapter: restHttpAdapter.execute' : 'restAdapter: restAdapter',
      ].join(', ')})',
    ];

    return 'public static ${codeGenUtils.method(
      returnType: swiftClientName,
      methodName: 'create',
      arguments: params,
      statements: statements,
    )}';
  }

  // ── Resolver base ───────────────────────────────────────────────────────────

  GLClassModel generateResolverBaseFile() => GLClassModel(
        imports: const ['Foundation'],
        body: swiftGraphLinkResolverBase(
          grammar.operationNameAsParameter,
          persistedQueries: grammar.persistedQueries,
          useGet: grammar.persistedQueriesUseGet,
        ),
      );

  // ── Operation-independent runtime files ─────────────────────────────────────
  //
  // `imports: ['Foundation']` covers Data/URL/URLSession/Date/NSNull/
  // JSONSerialization/String(data:encoding:) — every file below that touches
  // one of those needs it; `serializeGlClass` renders it via
  // `serializeImport('Foundation') => 'import Foundation'`.

  GLClassModel generateClientAdapterFile() => GLClassModel(
        imports: const ['Foundation'],
        body: grammar.operationNameAsParameter
            ? swiftGraphLinkClientAdapterWithOperationName
            : swiftGraphLinkClientAdapter,
      );

  GLClassModel generateJsonFile() => const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkJson);

  GLClassModel generateDecodeFile() => const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkDecode);

  GLClassModel generateCacheStoreFile() => const GLClassModel(body: swiftGraphLinkCacheStore);

  GLClassModel generateInMemoryCacheStoreFile() => const GLClassModel(body: swiftInMemoryGraphLinkCacheStore);

  GLClassModel generateCacheEntryFile() =>
      const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkCacheEntry);

  GLClassModel generateTagEntryFile() => const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkTagEntry);

  GLClassModel generatePartialQueryFile() =>
      const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkPartialQuery);

  GLClassModel generateExceptionFile() => const GLClassModel(body: swiftGraphLinkException);

  GLClassModel generateSha256File() {
    if (!grammar.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(imports: ['Foundation'], body: swiftSha256);
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!grammar.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      imports: const ['Foundation'],
      body: grammar.persistedQueriesUseGet ? '$swiftPersistedQueries\n$swiftPersistedQueriesGet' : swiftPersistedQueries,
    );
  }

  GLClassModel generateDefaultGetAdapterFile() {
    if (!grammar.persistedQueriesUseGet) {
      throw StateError('The GET adapter is only generated when persistedQueriesUseGet is enabled.');
    }
    return GLClassModel(
      imports: const ['Foundation'],
      body: swiftDefaultGraphLinkURLSessionGetAdapter(grammar.operationNameAsParameter),
    );
  }

  GLClassModel generateDefaultAdapterFile() => GLClassModel(
        imports: const ['Foundation'],
        body: swiftDefaultGraphLinkURLSessionAdapter(grammar.operationNameAsParameter),
      );

  // ── Operation classes ───────────────────────────────────────────────────────

  @override
  GLClassModel? getQueriesClass() => _buildClassForType(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() => _buildClassForType(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() => _buildClassForType(GLQueryType.subscription);

  GLClassModel? _buildClassForType(GLQueryType type) {
    final restOperations = _restOperations(type);
    final methods = [...buildOperationMethods(type), ...restOperations.map(_restSer.operationToMethod)];
    if (methods.isEmpty) return null;

    final className = classNameFromType(type);
    final ctorParams = _ctorParams(type);
    final ctorAssignments = _ctorAssignments(type);
    final extraFields = <String>[
      if (type == GLQueryType.mutation && grammar.hasUploadMutations)
        'private let multipartAdapter: GraphLinkMultipartAdapter',
      if (type == GLQueryType.subscription) 'private let handler: GraphLinkSubscriptionHandler',
    ];

    // `override` is only valid when the initializer's parameter list is a
    // verbatim match for GraphLinkResolverBase's own `(adapter:fragmentMap:
    // store:)` designated initializer. Mutations-with-uploads and every
    // subscription class insert an extra `multipartAdapter`/`wsAdapter`
    // parameter, which makes this a *new* designated initializer for the
    // subclass rather than an override — Swift rejects `override` there
    // ("does not override any initializer from its superclass").
    final isOverride = !(type == GLQueryType.subscription ||
        (type == GLQueryType.mutation && grammar.hasUploadMutations) ||
        grammar.persistedQueriesUseGet);
    final initKeyword = isOverride ? 'public override init' : 'public init';

    final initDecl = '$initKeyword(${ctorParams.join(', ')}) ${codeGenUtils.block(ctorAssignments)}';
    final classBody = [
      ...extraFields,
      if (extraFields.isNotEmpty) '',
      initDecl,
      '',
      methods.join('\n\n'),
    ];
    final base = restOperations.isEmpty ? 'GraphLinkResolverBase' : 'GraphLinkRestResolver';
    final body = 'public final class $className: $base, @unchecked Sendable ${codeGenUtils.block(classBody)}';

    return GLClassModel(imports: grammar.scalarImportsOfOperationType(type).toList(), body: body);
  }

  List<String> _ctorParams(GLQueryType type) {
    return [
      'adapter: @escaping GraphLinkClientAdapter',
      if (type != GLQueryType.subscription && grammar.persistedQueriesUseGet)
        'getAdapter: @escaping GraphLinkClientAdapter',
      if (type == GLQueryType.subscription) 'wsAdapter: any GraphLinkWebSocketAdapter',
      if (type == GLQueryType.mutation && grammar.hasUploadMutations) 'multipartAdapter: @escaping GraphLinkMultipartAdapter',
      'fragmentMap: [String: String]',
      'store: any GraphLinkCacheStore',
    ];
  }

  List<String> _ctorAssignments(GLQueryType type) {
    return [
      if (type == GLQueryType.mutation && grammar.hasUploadMutations) 'self.multipartAdapter = multipartAdapter',
      if (type == GLQueryType.subscription) 'self.handler = GraphLinkSubscriptionHandler(adapter: wsAdapter)',
      codeGenUtils.callExpression('super.init', [
        'adapter: adapter',
        if (type != GLQueryType.subscription && grammar.persistedQueriesUseGet) 'getAdapter: getAdapter',
        'fragmentMap: fragmentMap',
        'store: store',
      ]),
    ];
  }

  // ── Boilerplate file models ─────────────────────────────────────────────────

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(imports: ['Foundation'], body: swiftGLUpload);

  GLClassModel generateRestFile() => const GLClassModel(imports: ['Foundation'], body: swiftRestFile);

  GLClassModel generateRestResolverFile() => GLClassModel(
        imports: const ['Foundation'],
        body: '$swiftRestResolver\n${swiftRestNoGraphQL(grammar.operationNameAsParameter)}',
      );

  GLClassModel generateRestAdapterFile() =>
      const GLClassModel(imports: ['Foundation'], body: swiftRestUrlSessionAdapter);

  GLClassModel generateUploadProgressCallbackFile() => const GLClassModel(body: swiftUploadProgressCallback);

  GLClassModel generateMultipartAdapterFile() => const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkMultipartAdapter);

  GLClassModel generateDefaultMultipartAdapterFile() =>
      const GLClassModel(imports: ['Foundation'], body: swiftDefaultGraphLinkURLSessionMultipartAdapter);

  GLClassModel generateWebSocketAdapterFile() => const GLClassModel(body: swiftGraphLinkWebSocketAdapter);

  GLClassModel generateDefaultWebSocketAdapterFile() =>
      const GLClassModel(imports: ['Foundation'], body: swiftDefaultGraphLinkWebSocketAdapter);

  GLClassModel generateWsMessageTypesFile() => const GLClassModel(body: swiftGraphlinkWsMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() => const GLClassModel(imports: ['Foundation'], body: swiftGraphLinkSubscriptionHandler);
}
