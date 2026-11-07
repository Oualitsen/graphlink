import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_rest_operation_serializer.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_runtime_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_adapters_serializer.dart';

class KotlinClientSerializer extends GLClientSerializer {
  late final runtime = KotlinClientRuntimeSerializer(this);
  late final adapters = KotlinClientAdaptersSerializer(this);

  final GLParser _grammar;

  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();

  final KotlinWsAdapter wsAdapter;

  final KotlinWsAdapter restHttpAdapter;

  late final KotlinClientContext _ctx;

  late final KotlinClientOperationSerializer _opSer;

  late final KotlinRestOperationSerializer _restSer;

  GLImportContainer? _activeContainer;

  KotlinClientSerializer(
    this._grammar,
    GLSerializer serializer, {
    this.wsAdapter = KotlinWsAdapter.okhttp,
    KotlinWsAdapter? restHttpAdapter,
    bool commaQueryLists = false,
    bool bracketFormNesting = false,
  })  : restHttpAdapter = restHttpAdapter ?? wsAdapter,
        super(serializer, GLGraphqlSerializer(_grammar, false)) {
    _ctx = KotlinClientContext(_grammar, codeGenUtils, gqlSerializer, serializer);
    _opSer = KotlinClientOperationSerializer(_ctx);
    _restSer = KotlinRestOperationSerializer(
      _grammar,
      codeGenUtils,
      serializer as KotlinSerializer,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _grammar.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) => _grammar.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get hasRest => _grammar.restOperations.isNotEmpty;

  bool get _hasGraphQL => GLQueryType.values.any(_grammar.hasQueryType);

  bool get generatesRestAdapter => hasRest && restHttpAdapter != KotlinWsAdapter.none;

  List<GLToken> _restTokens(GLQueryType type) {
    final tokens = <GLToken>[];
    for (final operation in _restOperations(type)) {
      final names = [
        operation.field.type.firstType.token,
        ...operation.arguments.map((a) => a.argument.type.firstType.token),
      ];
      for (final name in names) {
        if (_grammar.isRestImportableType(name)) {
          final token = _grammar.getTokenByKey(name);
          if (token != null) tokens.add(token);
        }
      }
    }
    return tokens;
  }

  @override
  String renderQueryMethod(GLQueryDefinition def) =>
      _opSer.queryToMethod(def, _activeContainer!);

  @override
  String renderMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def, _activeContainer!);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def, _activeContainer!);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) =>
      _opSer.subscriptionToMethod(def, _activeContainer!);

  // ── Main client class ───────────────────────────────────────────────────────

  @override
  GLClassModel generateClient({bool hasDefaultAdapters = true}) {
    final container = GLImportContainer();
    container.importDepencies.addAll([
      _grammar.getTokenByKey('GraphLinkClientAdapter')!,
      _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
    ]);

    final fields = <String>[
      'private val fragmentMap = mutableMapOf<String, String>()',
      if (!_hasGraphQL) 'private val adapter: GraphLinkClientAdapter = GraphLinkNoGraphQL',
      if (_hasOperations(GLQueryType.query))
        'val queries: ${_classNameFor(GLQueryType.query)}',
      if (_hasOperations(GLQueryType.mutation))
        'val mutations: ${_classNameFor(GLQueryType.mutation)}',
      if (_grammar.hasSubscriptions)
        'val subscriptions: ${_classNameFor(GLQueryType.subscription)}',
    ];

    final initBody = <String>[
      if (_hasOperations(GLQueryType.query)) ...[
        'queries = ${_classNameFor(GLQueryType.query)}(adapter, ${_getAdapterArg}fragmentMap, encoder, decoder, store)',
        if (_restOperations(GLQueryType.query).isNotEmpty) 'queries.restAdapter = restAdapter',
      ],
      if (_hasOperations(GLQueryType.mutation)) ...[
        'mutations = ${_classNameFor(GLQueryType.mutation)}(adapter, $_getAdapterArg${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}fragmentMap, encoder, decoder, store)',
        if (_restOperations(GLQueryType.mutation).isNotEmpty) 'mutations.restAdapter = restAdapter',
      ],
      if (_grammar.hasSubscriptions)
        'subscriptions = ${_classNameFor(GLQueryType.subscription)}(adapter, wsAdapter, fragmentMap, encoder, decoder, store)',
      ..._grammar.usedFragments
          .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
          .map((f) =>
              'fragmentMap["${f.tokenInfo}"] = "${gqlSerializer.serializeFragmentDefinitionBase(f).escapeForStringLiteral()}"'),
    ];

    final primaryCtorArgs = [
      if (_hasGraphQL) 'private val adapter: GraphLinkClientAdapter',
      if (_hasGraphQL && _grammar.persistedQueriesUseGet) 'private val getAdapter: GraphLinkClientAdapter',
      if (_grammar.hasSubscriptions) 'private val wsAdapter: GraphLinkWebSocketAdapter',
      if (_grammar.hasUploadMutations) 'private val multipartAdapter: GraphLinkMultipartAdapter',
      if (hasRest) 'private val restAdapter: GLRestAdapter',
      'private val encoder: GraphLinkJsonEncoder',
      'private val decoder: GraphLinkJsonDecoder',
      'private val store: GraphLinkCacheStore = InMemoryGraphLinkCacheStore()',
    ];

    final body = StringBuffer();
    body.writeln(codeGenUtils.openClass(
      name: kotlinClientName,
      params: primaryCtorArgs,
      body: [
        ...fields,
        '',
        'init ${codeGenUtils.block(initBody)}',
        if (hasDefaultAdapters) ..._convenienceFactories(),
      ],
    ));

    return GLClassModel(
      importDepencies: container.importDepencies,
      imports: container.imports,
      body: body.toString(),
    );
  }

  List<String> _convenienceFactories() {
    const codec = 'KotlinxSerializationGraphLinkJsonCodec()';
    final hasSubs = _grammar.hasSubscriptions;
    final hasUploads = _grammar.hasUploadMutations;
    final hasGraphQL = _hasGraphQL;
    final restDefault = generatesRestAdapter;
    final urlParams = hasGraphQL ? ['url: String', if (hasSubs) 'wsUrl: String'] : <String>[];
    final restParams = !hasRest ? <String>[] : restDefault ? ['restBaseUrl: String'] : ['restAdapter: GLRestAdapter'];
    String restArg(bool withHeaders) => restDefault
        ? 'DefaultGraphLinkRestAdapter(restBaseUrl${withHeaders ? ', headersProvider' : ''})'
        : 'restAdapter';

    List<String> callArgs(String adapterExpr, String wsExpr, {String getArgs = '', bool headers = false}) {
      final getExpr = hasGraphQL && _grammar.persistedQueriesUseGet ? ', DefaultGraphLinkGetAdapter(url$getArgs)' : '';
      final rest = hasRest ? [restArg(headers)] : <String>[];
      if (!hasGraphQL) {
        return ['return ${codeGenUtils.callExpression(kotlinClientName, [...rest, 'encoder', 'decoder'])}'];
      }
      if (hasUploads) {
        return [
          codeGenUtils.constDecl('a', adapterExpr),
          'return ${codeGenUtils.callExpression(kotlinClientName, ['a$getExpr${hasSubs ? ', $wsExpr' : ''}', 'a', ...rest, 'encoder', 'decoder'])}',
        ];
      }
      return [
        'return ${codeGenUtils.callExpression(kotlinClientName, ['$adapterExpr$getExpr${hasSubs ? ', $wsExpr' : ''}', ...rest, 'encoder', 'decoder'])}'
      ];
    }

    String factory(List<String> arguments, List<String> statements) => codeGenUtils.createMethod(
          methodName: 'create',
          returnType: kotlinClientName,
          arguments: arguments,
          statements: statements,
        );

    const codecArgs = ['encoder: GraphLinkJsonEncoder', 'decoder: GraphLinkJsonDecoder'];
    const headersArg = 'headersProvider: () -> Map<String, String>';
    final adapterExpr = hasGraphQL ? 'DefaultGraphLinkClientAdapter(url, decoder)' : '';
    final adapterWithHeaders = hasGraphQL ? 'DefaultGraphLinkClientAdapter(url, decoder, headersProvider)' : '';
    final wsExpr = hasSubs ? 'DefaultGraphLinkWebSocketAdapter(wsUrl)' : '';
    final wsWithHeaders = hasSubs ? 'DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)' : '';
    final forwarded = [
      if (hasGraphQL) 'url',
      if (hasSubs) 'ws',
      if (hasRest) restDefault ? 'restBaseUrl' : 'restAdapter',
    ];

    return [
      '',
      codeGenUtils.companionObject([
        factory([...urlParams, ...restParams, ...codecArgs], callArgs(adapterExpr, wsExpr)),
        factory([...urlParams, ...restParams, headersArg, ...codecArgs],
            callArgs(adapterWithHeaders, wsWithHeaders, getArgs: ', headersProvider', headers: true)),
        factory([
          if (hasGraphQL) 'url: String',
          ...restParams,
        ], [
          if (hasSubs) codeGenUtils.constDecl('ws', 'url.replaceFirst("http", "ws")'),
          'return ${codeGenUtils.callExpression('create', [...forwarded, codec, codec])}',
        ]),
      ]),
    ];
  }

  // ── Resolver base ───────────────────────────────────────────────────────────

  String get _getAdapterArg => _grammar.persistedQueriesUseGet ? 'getAdapter, ' : '';

  @override
  GLClassModel? getQueriesClass() => _buildClassForType(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() => _buildClassForType(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() => _buildClassForType(GLQueryType.subscription);

  GLClassModel? _buildClassForType(GLQueryType type) {
    final container = GLImportContainer();
    _activeContainer = container;

    container.importDepencies.addAll([
      _grammar.getTypeByName('GraphLinkClientAdapter')!,
      _grammar.getTypeByName('GraphLinkJsonEncoder')!,
      _grammar.getTypeByName('GraphLinkJsonDecoder')!,
    ]);

    final restOperations = _restOperations(type);
    final methods = [
      ...buildOperationMethods(type),
      ...restOperations.map(_restSer.operationToMethod),
    ];
    if (methods.isEmpty) return null;

    final ctorParams = _ctorParams(type);
    final extraFields = <String>[
      if (type == GLQueryType.subscription)
        'private lateinit var handler: GraphLinkSubscriptionHandler',
    ];

    final body = codeGenUtils.openClass(
      name: _classNameFor(type),
      params: ctorParams,
      interfaces: [_superCtorCall(type, restOperations.isNotEmpty)],
      body: [
        ...extraFields,
        '',
        if (type == GLQueryType.subscription)
          'init ${codeGenUtils.block(['handler = GraphLinkSubscriptionHandler(wsAdapter, decoder, encoder)'])}',
        '',
        ...methods,
      ],
    );

    return GLClassModel(
      importDepencies: {
        ..._queryImports(type),
        ..._restTokens(type),
        ...container.importDepencies,
      }.toList(),
      imports: [...container.imports, ..._grammar.scalarImportsOfOperationType(type)],
      body: body,
    );
  }

  List<String> _ctorParams(GLQueryType type) {
    return [
      'adapter: GraphLinkClientAdapter',
      if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet)
        'getAdapter: GraphLinkClientAdapter',
      if (type == GLQueryType.subscription) 'wsAdapter: GraphLinkWebSocketAdapter',
      if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
        'private val multipartAdapter: GraphLinkMultipartAdapter',
      'fragmentMap: Map<String, String>',
      'encoder: GraphLinkJsonEncoder',
      'decoder: GraphLinkJsonDecoder',
      'store: GraphLinkCacheStore',
    ];
  }

  String _superCtorCall(GLQueryType type, [bool rest = false]) =>
      codeGenUtils.callExpression(rest ? 'GraphLinkRestResolver' : 'GraphLinkResolverBase', [
        'adapter',
        'fragmentMap',
        'store',
        'encoder',
        'decoder',
        if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet) 'getAdapter',
      ]);

  Set<GLToken> _queryImports(GLQueryType type) =>
      schemaTokensFor(type).toSet();

  // ── REST files ──────────────────────────────────────────────────────────────

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: kotlinGLUpload);

  String _classNameFor(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return 'GraphLinkQueries';
      case GLQueryType.mutation:
        return 'GraphLinkMutations';
      case GLQueryType.subscription:
        return 'GraphLinkSubscriptions';
    }
  }

  String get fileExtension => '.kt';

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    return ['GraphLinkJsonEncoder', 'GraphLinkJsonDecoder', 'GraphLinkClientAdapter']
        .map(g.getTokenByKey)
        .whereType<GLToken>()
        .toSet();
  }

  GLParser get grammar => _grammar;
}
