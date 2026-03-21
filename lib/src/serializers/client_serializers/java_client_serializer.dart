import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/gl_client_serilaizer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';

const clientName = 'GraphLinkClient';
const clientExceptionName = 'GLinkException';
const clientExceptionNameRef = '${clientName}.${clientExceptionName}';
const _subscriptionListenerName = 'GraphLinkSubscriptionListener';
const _subscriptionListenerRef = '${clientName}.${_subscriptionListenerName}';

class JavaClientSerializer extends GLClientSerilaizer {
  final GLGrammar _grammar;
  final codeGenUtils = JavaCodeGenUtils();

  final GLGraphqSerializer gqlSerializer;

  JavaClientSerializer(this._grammar, GLSerializer serializer)
      : gqlSerializer = GLGraphqSerializer(_grammar, false),
        super(serializer);

  @override
  String generateClient(String importPrefix) {
    var imports = serializeImports(_grammar, importPrefix);

    var buffer = StringBuffer();
    for (var i in [
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.list,
      JavaImports.collectors,
      JavaImports.arrays,
      JavaImports.collections,
      if (_grammar.hasSubscriptions) ...[
        JavaImports.uuid,
        JavaImports.arrayList,
      ]
    ]) {
      buffer.writeln('import ${i};');
    }
    buffer.writeln(imports);

    buffer.writeln(codeGenUtils.createClass(className: clientName, statements: [
      'final Map<String, String> _fragmMap = new HashMap<>();',
      'final GraphLinkClientAdapter adapter;',
      'final GraphLinkJsonEncoder encoder;',
      'final GraphLinkJsonDecoder decoder;',
      if (_grammar.hasQueries) 'public final ${classNameFromType(GLQueryType.query)} queries;',
      if (_grammar.hasMutations) 'public final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_grammar.hasSubscriptions) 'public final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      codeGenUtils.createMethod(
        returnType: "public",
        methodName: clientName,
        arguments: [
          _adapterDeclaration(),
          if (_grammar.hasSubscriptions) 'GraphLinkGraphLinkWebSocketAdapter wsAdapter'
        ],
        statements: [
          'this.adapter = adapter;',
          'this.encoder = encoder;',
          'this.decoder = decoder;',
          if (_grammar.hasQueries)
            "queries = new ${classNameFromType(GLQueryType.query)}(adapter, _fragmMap, encoder, decoder);",
          if (_grammar.hasMutations)
            "mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, _fragmMap, encoder, decoder);",
          if (_grammar.hasSubscriptions)
            "subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, _fragmMap, encoder, decoder);",
          ..._grammar.fragments.values.map((value) =>
              '_fragmMap.put("${value.tokenInfo}", "${gqlSerializer.serializeFragmentDefinitionBase(value)}");'),
        ],
      ),
      '',
      ...GLQueryType.values.map((e) => generateQueriesClassByType(e)).where((e) => e != null).map((e) => e!),
      codeGenUtils.createClass(
        staticClass: true,
        className: "${clientExceptionName} extends RuntimeException",
        statements: [
          'private final List<GraphLinkError> errors;',
          codeGenUtils.createMethod(returnType: 'public', methodName: clientExceptionName, arguments: [
            'List<GraphLinkError> errors',
          ], statements: [
            'this.errors = errors;'
          ]),
          codeGenUtils.createMethod(returnType: 'private', methodName: clientExceptionName, arguments: [
            'Exception ex',
          ], statements: [
            'super(ex);',
            'errors = Collections.emptyList();'
          ]),
          codeGenUtils.createMethod(
              returnType: 'public List<GraphLinkError>',
              methodName: 'getErrors',
              arguments: [],
              statements: ['return errors;']),
          codeGenUtils.createMethod(returnType: 'static ${clientExceptionName}', methodName: 'of', arguments: [
            'List<?> errors'
          ], statements: [
            'return new ${clientExceptionName}(errors.stream().map(e -> GraphLinkError.fromJson((Map<String, Object>)e)).collect(Collectors.toList()));'
          ])
        ],
      ),
      if (_grammar.hasSubscriptions) _gqSubscriptionListener
    ]));

    buffer.writeln(serializeSubscriptions().ident());
    return buffer.toString();
  }

  String _adapterDeclaration() {
    return 'GraphLinkClientAdapter adapter, GraphLinkJsonEncoder encoder, GraphLinkJsonDecoder decoder';
  }

  String? generateQueriesClassByType(GLQueryType type) {
    var queries = _grammar.queries.values;
    var queryList = queries.where((element) => element.type == type && _grammar.hasQueryType(type)).toList();
    if (queryList.isEmpty) {
      return null;
    }

    return codeGenUtils.createClass(staticClass: true, className: classNameFromType(type), statements: [
      ...declareAdapter(type),
      "final Map<String, String> fragmentMap;",
      "final GraphLinkJsonEncoder encoder;",
      "final GraphLinkJsonDecoder decoder;",
      codeGenUtils.createMethod(
          returnType: 'public',
          methodName: classNameFromType(type),
          arguments: _declareConstructorArgs(type),
          statements: [
            'this.adapter = adapter;',
            'this.fragmentMap = fragmentMap;',
            'this.encoder = encoder;',
            'this.decoder = decoder;',
            if (type == GLQueryType.subscription) '_handler = new SubscriptionHandler(adapter, decoder, encoder);',
          ]),
      ...queryList.map((e) => queryToMethod(e))
    ]);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    if (type == GLQueryType.subscription) {
      return [
        'GraphLinkGraphLinkWebSocketAdapter adapter',
        'Map<String, String> fragmentMap',
        'GraphLinkJsonEncoder encoder',
        'GraphLinkJsonDecoder decoder',
      ];
    }
    return [
      'GraphLinkClientAdapter adapter',
      'Map<String, String> fragmentMap',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
    ];
  }

  List<String> declareAdapter(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
      case GLQueryType.mutation:
        return ["final GraphLinkClientAdapter adapter;"];
      case GLQueryType.subscription:
        return ["final SubscriptionHandler _handler;", "final GraphLinkGraphLinkWebSocketAdapter adapter;"];
    }
  }

  String queryToMethod(GLQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String operationName = "${def.tokenInfo}";',
          "List<String> fragsValues = Arrays.asList(${def.fragments(_grammar).map((e) => 'fragmentMap.get("${e.token}")').join(", ")});",
          'String query = "${gqlSerializer.serializeQueryDefinition(def)} " + String.join(" ", fragsValues);',
          generateVariables(def),
          "GraphLinkPayload payload = GraphLinkPayload.builder().query(query).operationName(operationName).variables(variables).build();",
          _serializeAdapterCall(def)
        ]);
  }

  String generateVariables(GLQueryDefinition def) {
    var buffer = StringBuffer("Map<String, Object> variables = new HashMap<>();");
    buffer.writeln();
    def.arguments
        .map((e) => 'variables.put("${e.dartArgumentName}", ${_serializeArgumentValue(def, e.token)});')
        .forEach(buffer.writeln);

    return buffer.toString();
  }

  String _serializeAdapterCall(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      var method = codeGenUtils.createMethod(
          methodName:
              '${_subscriptionListenerRef}<Map<String, Object>> rawListener = new ${_subscriptionListenerRef}<Map<String, Object>>',
          statements: [
            '@Override',
            codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onMessage',
              arguments: ['Map<String, Object> response'],
              statements: ['listener.onMessage(${def.typeDefinition?.token}.fromJson(response));'],
            ),
            '@Override',
            codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onComplete',
              arguments: [],
              statements: ['listener.onComplete();'],
            ),
            '@Override',
            codeGenUtils.createMethod(
              returnType: 'public void',
              methodName: 'onError',
              arguments: ['${clientExceptionNameRef} error'],
              statements: ['listener.onError(error);'],
            )
          ]);
      return ['${method};', '_handler.handlePayload(payload, rawListener);'].join('\n');
    }
    return [
      "String encodedPayload = encoder.encode(payload);",
      "String responseText = adapter.execute(encodedPayload);",
      "Map<String, Object> decodedResponse = decoder.decode(responseText);",
      codeGenUtils.ifStatement(condition: 'decodedResponse.containsKey("errors")', ifBlockStatements: [
        'throw ${clientExceptionName}.of((List)decodedResponse.get("errors"));'
      ], elseBlockStatements: [
        'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson((Map<String, Object>)decodedResponse.get("data"));'
      ])
    ].join("\n");
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GLType type) {
    if (_grammar.inputTypeRequiresProjection(type)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    }
    if (_grammar.isEnum(type.token)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    } else {
      return argName;
    }
  }

  String _getNullableText(GLType type) {
    if (type.nullable) {
      return "?";
    }
    return "";
  }

  List<String> getArguments(GLQueryDefinition def) {
    List<String> result;
    if (def.arguments.isEmpty) {
      result = [];
    }
    result = def.arguments.map((e) => "${serializer.serializeType(e.type, false)} ${e.dartArgumentName}").toList();
    if (def.type == GLQueryType.subscription) {
      result.add('${_subscriptionListenerRef}<${def.typeDefinition?.token}> listener');
    }
    return result;
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GLQueryType.subscription) {
      return "void";
    }
    return gen.tokenInfo.token;
  }

  String serializeSubscriptions() {
    if (!_grammar.hasSubscriptions) {
      return "";
    }
    return """
$_subscriptionHandler
""";
  }

  String get fileExtension => '.java';

  @override
  Set<GLToken> getImportDependecies(GLGrammar g) {
    var result = {...super.getImportDependecies(g)};
    result.addAll(
        ['GraphLinkJsonEncoder', 'GraphLinkJsonDecoder', 'GraphLinkClientAdapter'].map((e) => g.getTypeByName(e)!));
    var adapter = g.getTokenByKey('GraphLinkGraphLinkWebSocketAdapter');
    if (adapter != null) {
      result.add(adapter);
    }
    return result;
  }
}

const _gqSubscriptionListener = '''
public interface ${_subscriptionListenerName}<T> {
  void onMessage(T response) ;
  default void  onComplete(){}
  default void  onError(${clientExceptionNameRef} error) {}
}
''';

const _subscriptionHandler = '''

class GraphqlWsMessageTypes {
  /// Client initializes connection.
  /// Example: { "type": "connection_init", "payload": { "authToken": "abc123" } }
  public static final String connectionInit = "connection_init";

  /// Server acknowledges connection.
  /// Example: { "type": "connection_ack" }
  public static final String connectionAck = "connection_ack";

  /// Client subscribes to an operation.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "subscribe",
  ///   "payload": { "query": "...", "variables": {} }
  /// }
  public static final String subscribe = "subscribe";

  /// Client or server pings for keep-alive.
  /// Example: { "type": "ping", "payload": {} }
  public static final String ping = "ping";

  /// Response to ping.
  /// Example: { "type": "pong" }
  public static final String pong = "pong";

  /// Server sends subscription data.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "next",
  ///   "payload": { "data": { "newMessage": { "id": "42", "content": "Hi" } } }
  /// }
  public static final String next = "next";

  /// Server sends a fatal error for a subscription.
  /// Example: { "id": "1", "type": "error", "payload": { "message": "Validation failed" } }
  public static final String error = "error";

  /// Client or server completes subscription.
  /// Example: { "id": "1", "type": "complete" }
  public static final String complete = "complete";
}


class SubscriptionHandler {

  // we have to think about synchronization here
  private final Map<String, ${_subscriptionListenerRef}<Map<String, Object>>> listeners = new HashMap<>();
  private final Map<String, GraphLinkPayload> payloadsToHandle = new HashMap<>();

  private final GraphLinkGraphLinkWebSocketAdapter adapter;
  private final GraphLinkJsonDecoder decoder;
  private final GraphLinkJsonEncoder encoder;
  private GraphLinkAckStatus ackStatus = GraphLinkAckStatus.none;


  SubscriptionHandler(GraphLinkGraphLinkWebSocketAdapter adapter, GraphLinkJsonDecoder decoder, GraphLinkJsonEncoder encoder) {
    this.adapter = adapter;
    this.decoder = decoder;
    this.encoder = encoder;
    adapter.onMessage(this::onMessage);
  }

  String getConnectionInit(String id) {
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.connectionInit)
        .id(id)
        .build());
  }

  String getPongMessage(String id) {
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.pong)
        .id(id)
        .build());
  }

  String getSubscriptionMessage(String id) {
    GraphLinkPayload payload = payloadsToHandle.get(id);
    GraphLinkSubscriptionPayload subscriptionPayload = GraphLinkSubscriptionPayload.builder()
        .query(payload.getQuery())
        .operationName(payload.getOperationName())
        .variables(payload.getVariables())

        .build();
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.subscribe)
        .payload(subscriptionPayload)
        .id(id)
        .build());
  }


  public synchronized void initConnection(String id, GraphLinkPayload payload) {
    switch (ackStatus) {
      case none:
        addPayload(id, payload);
        ackStatus = GraphLinkAckStatus.progress;
        adapter.connect((obj) -> {
          String connectionInit = getConnectionInit(id);
          System.out.println("Sending connectionInit = " + connectionInit);
          adapter.sendMessage(connectionInit);
        }, (t) -> {
          System.out.println("Connection failed!");
        });
        //
        break;
      case progress:
        System.out.println("in progress ....");
        addPayload(id, payload);
        break;
      case acknoledged:
        adapter.sendMessage(getSubscriptionMessage(id));
        break;
    }
  }

  private void addPayload(String id, GraphLinkPayload payload) {
    synchronized (payloadsToHandle) {
      payloadsToHandle.put(id, payload);
    }
  }

  GraphLinkPayload getPayload(String id) {
    return payloadsToHandle.get(id);
  }


  private GraphLinkSubscriptionErrorMessageBase parseEvent(String event) {
    Map<String, Object> map = decoder.decode(event);
    Object payload = map.get("payload");
    GraphLinkSubscriptionErrorMessageBase result;
    if (payload instanceof Map) {
      result = GraphLinkSubscriptionMessage.fromJson(map);
    } else {
      result = GraphLinkSubscriptionErrorMessage.fromJson(map);
    }
    return result;
  }


  public void handlePayload(GraphLinkPayload payload, ${_subscriptionListenerRef}<Map<String, Object>> listener) {
    String uuid = UUID.randomUUID().toString();
    synchronized (listeners) {
      listeners.put(uuid, listener);
    }
    initConnection(uuid, payload);
  }


  public void onMessage(String message) {
    GraphLinkSubscriptionErrorMessageBase event = parseEvent(message);
    String type = event.getType();
    switch (type) {
      case GraphqlWsMessageTypes.connectionAck:
        handleConnectionAck();
        break;
      case GraphqlWsMessageTypes.subscribe:
        System.out.println("handle subscription here " + event.getId());
        break;
      case GraphqlWsMessageTypes.ping:
        adapter.sendMessage(getPongMessage(event.getId()));
        break;
      case GraphqlWsMessageTypes.next:
        handleNextMessage((GraphLinkSubscriptionMessage) event);
        break;
      case GraphqlWsMessageTypes.error:
        System.out.println("Evenet class = "+ event.getClass());
        handleError((GraphLinkSubscriptionErrorMessage)event);
        break;
      case GraphqlWsMessageTypes.complete:
        handleComplete(event.getId());
        break;
    }
  }

  void handleError(GraphLinkSubscriptionErrorMessage error) {
    ${_subscriptionListenerRef}<Map<String, Object>> listener;
    synchronized (listeners) {
      listener = listeners.remove(error.getId());
    }

    if (listener != null) {
      listener.onError(new ${clientExceptionNameRef}(error.getPayload()));
    }
  }

  void handleComplete(String id) {
    ${_subscriptionListenerRef}<Map<String, Object>> removedListener;
    synchronized (listeners) {
      removedListener = listeners.remove(id);
    }
    if(removedListener != null) {
      removedListener.onComplete();
    }
  }

  synchronized void  handleConnectionAck() {
    this.ackStatus = GraphLinkAckStatus.acknoledged;
    List<String> handledPayloadIds = new ArrayList<>(payloadsToHandle.size());
    this.payloadsToHandle.forEach((uuid, payload) -> {
      adapter.sendMessage(getSubscriptionMessage(uuid));
      handledPayloadIds.add(uuid);
    });

    handledPayloadIds.forEach(payloadsToHandle::remove);

  }

  private void handleNextMessage(GraphLinkSubscriptionMessage message) {
    String id = message.getId();
    // no need for synchronization!
    ${_subscriptionListenerRef}<Map<String, Object>> listener = listeners.get(id);
    if (listener != null) {

      System.out.println(
          "Should call the lister here with data = " + message.getPayload().getData());
      listener.onMessage(message.getPayload().getData());
    }
  }


}

''';
