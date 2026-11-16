import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/java/java_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  scalar Void @glVoid

  enum Color { RED GREEN }

  input Filter { tag: String colors: [Color!] }
  input ItemInput { name: String! qty: Int! }

  type Item { id: ID! name: String! color: Color }

  type Query {
    item(id: ID!): Item @glRest(path: "/items/{id}")
    search(filter: Filter @glRestParam, limit: Int = 10 @glRestParam, color: Color @glRestParam): [Item!]! @glRest(path: "/items")
    greeting(name: String! @glRestParam): String! @glRest(path: "/greeting")
    note(text: String! @glRestHeader(name: "X-Text")): String! @glRest(path: "/note", response: TEXT)
    graphqlItem(id: ID!): Item
  }

  type Mutation {
    create(input: ItemInput! @glRestBody): Item! @glRest(path: "/items")
    remove(id: ID!): Void @glRest(path: "/items/{id}", method: DELETE)
  }
''';

const _uploadSchema = '''
  directive @glUpload on SCALAR
  scalar Upload @glUpload

  type Info { size: Int! }

  type Query { ping: Boolean! }

  type Mutation {
    upload(file: Upload! @glRestPart, label: String @glRestPart, times: Int @glRestPart): Info! @glRest(path: "/upload")
    many(files: [Upload!]! @glRestPart): [Info!]! @glRest(path: "/many")
    optional(file: Upload @glRestPart): Info! @glRest(path: "/optional")
    raw(id: ID!, file: Upload! @glRestBody): Info! @glRest(path: "/raw/{id}", method: PUT)
  }
''';

GLParser _parse(String schema) => GLParser(mode: CodeGenerationMode.server)..parse(schema);

String _java(String name, {bool reactive = false, String schema = _schema}) {
  final parser = _parse(schema);
  final serializer = JavaSpringServerSerializer(parser, packageName: 'app', reactive: reactive, generateSchema: true);
  return serializer.serializeRestController(parser.restControllers[name]!);
}

String _kotlin(String name, {bool blocking = true, String schema = _schema}) {
  final parser = _parse(schema);
  final serializer = KotlinSpringServerSerializer(parser, packageName: 'app', blockingServices: blocking, generateSchema: true);
  return serializer.serializeRestController(parser.restControllers[name]!);
}

ExpressApolloServerSerializer _express(GLParser parser) =>
    ExpressApolloServerSerializer(parser, TypeScriptSerializer(parser, importPrefix: ''), ExpressApolloServerConfig());

void main() {
  group('controllers', () {
    late GLParser parser;
    setUpAll(() => parser = _parse(_schema));

    test('the GraphQL controller keeps only the GraphQL operations of the service', () {
      expect(parser.controllers['ItemServiceController']!.fields.map((f) => f.name.token), ['graphqlItem']);
    });

    test('a service with only REST operations has no GraphQL controller', () {
      expect(parser.controllers.containsKey('GreetingServiceController'), isFalse);
      expect(parser.restControllers.keys, containsAll(['ItemServiceRestController', 'GreetingServiceRestController']));
    });

    test('the service interface still carries the REST operations', () {
      expect(parser.services['ItemService']!.fields.map((f) => f.name.token), containsAll(['item', 'search', 'create', 'graphqlItem']));
    });

    test('REST operations are not in the GraphQL schema', () {
      final schema = GLGraphqlSerializer(parser).generateSchema();
      expect(schema, contains('graphqlItem'));
      expect(schema, isNot(contains('greeting')));
      expect(schema, isNot(contains('search(')));
      expect(schema, isNot(contains('scalar Void')));
    });

    test('a Query left without fields keeps a valid type while Mutation has GraphQL operations', () {
      final mixed = _parse('''
        type Query { ping: Boolean! @glRest(path: "/ping") }
        type Mutation { pong: Boolean! }
      ''');
      expect(GLGraphqlSerializer(mixed).generateSchema(), contains('_glRestOnly: Boolean'));
    });
  });

  group('a schema with REST operations only has no GraphQL part', () {
    const restOnly = 'type Query { ping: Boolean! @glRest(path: "/ping") }';

    test('no controller, no schema, no stub field', () {
      final parser = _parse(restOnly);
      expect(parser.restOnly, isTrue);
      expect(parser.controllers, isEmpty);
      expect(parser.restControllers.keys, ['PingServiceRestController']);
      final spring = JavaSpringServerSerializer(parser, packageName: 'app', generateSchema: true);
      expect(spring.serializeTypeDefs(), isEmpty);
    });

    test('the Express entry point has no Apollo, schema or resolvers', () {
      final entry = _express(_parse(restOnly)).serializeEntryPoint();
      expect(entry, contains('app.use(buildRestRouter(services));'));
      expect(entry, isNot(contains('ApolloServer')));
      expect(entry, isNot(contains('typeDefs')));
      expect(entry, isNot(contains('buildResolvers')));
    });

    test('a schema with a GraphQL operation is not REST only', () {
      expect(_parse(_schema).restOnly, isFalse);
    });
  });

  group('Java Spring MVC', () {
    late String items;
    setUpAll(() => items = _java('ItemServiceRestController'));

    test('is a separate @RestController on the same service', () {
      expect(items, contains('@RestController'));
      expect(items, contains('class ItemServiceRestController'));
      expect(items, contains('private final ItemService itemService;'));
    });

    test('binds a path variable', () {
      expect(items, contains('@GetMapping(value = "/items/{id}")'));
      expect(items, contains('@PathVariable(name = "id") String id'));
    });

    test('binds a spread input object, a defaulted scalar and an enum', () {
      expect(items, contains('@RequestParam(name = "tag", required = false) String filter_tag'));
      expect(items, contains('@RequestParam(name = "colors", required = false) List<String> filter_colors'));
      expect(items, contains('@RequestParam(name = "limit", required = false, defaultValue = "10")'));
      expect(items, contains('@RequestParam(name = "color", required = false) String colorWire'));
      expect(items, contains('filterWire.isEmpty() ? null : GraphLinkRest.decode(() -> Filter.fromJson('));
      expect(items, contains('Color.fromJson((String)colorWire)'));
    });

    test('converts a JSON body from a map and the result back to a map', () {
      expect(items, contains('@RequestBody(required = true) Map<String, Object> inputWire'));
      expect(items, contains('GraphLinkRest.decode(() -> ItemInput.fromJson((Map<String, Object>)inputWire))'));
      expect(items, contains('__gl_result__ == null ? null : __gl_result__.toJson()'));
    });

    test('a Void operation answers 204', () {
      final remove = _java('RemoveServiceRestController');
      expect(remove, contains('@DeleteMapping(value = "/items/{id}")'));
      expect(remove, contains('@ResponseStatus(HttpStatus.NO_CONTENT)'));
    });

    test('a String result travels as a JSON string, a TEXT result as text', () {
      expect(_java('GreetingServiceRestController'), contains('GraphLinkRest.json('));
      final note = _java('NoteServiceRestController');
      expect(note, contains('@GetMapping(value = "/note", produces = "text/plain")'));
      expect(note, contains('@RequestHeader(name = "X-Text", required = true) String text'));
      expect(note, isNot(contains('GraphLinkRest.json(')));
    });
  });

  group('Java Spring reactive', () {
    test('returns Mono, collects lists and ends a Void operation with then()', () {
      final items = _java('ItemServiceRestController', reactive: true);
      expect(items, contains('Mono<Map<String, Object>> item('));
      expect(items, contains('.collectList()'));
      expect(items, isNot(contains('? extends')));
      final remove = _java('RemoveServiceRestController', reactive: true);
      expect(remove, contains('Mono<Void> remove('));
      expect(remove, contains('.then()'));
    });
  });

  group('Kotlin Spring', () {
    test('blocking services use plain functions', () {
      final items = _kotlin('ItemServiceRestController');
      expect(items, contains('fun item(@PathVariable(name = "id") id: String): Map<String, Any?>?'));
      expect(items, isNot(contains('suspend fun')));
      expect(items, contains('mutableMapOf<String, Any?>()'));
      expect(items, contains('GraphLinkRest.decode { '));
    });

    test('suspend services use suspend functions', () {
      expect(_kotlin('ItemServiceRestController', blocking: false), contains('suspend fun item('));
    });

    test('a TEXT result declares its media type with an array', () {
      expect(_kotlin('NoteServiceRestController'), contains('produces = ["text/plain"]'));
    });
  });

  group('Express', () {
    late GLParser parser;
    late String router;
    setUpAll(() {
      parser = _parse(_schema);
      router = _express(parser).serializeRestRouter();
    });

    test('registers a route per REST operation under its method', () {
      expect(router, contains('router.get("/items/:id"'));
      expect(router, contains('router.get("/items"'));
      expect(router, contains('router.post("/items"'));
      expect(router, contains('router.delete("/items/:id"'));
      expect(router, isNot(contains('graphqlItem')));
    });

    test('reads every argument from its part of the request', () {
      expect(router, contains('pathArg(req, "id", S.string)'));
      expect(router, contains('queryArg(req, "limit", S.int, { optional: true, defaultValue: 10 })'));
      expect(router, contains("headerArg(req, \"X-Text\", S.string, {})"));
      expect(router, contains('bodyArg(req, { k: \'ref\', name: "ItemInput" }, shapes, {})'));
    });

    test('describes the input objects it validates', () {
      expect(router, contains('ItemInput: {'));
      expect(router, contains('"qty": { shape: S.int, required: true }'));
    });

    test('answers the other methods of a known path with 405 and unknown paths under the prefix with 404', () {
      expect(router, contains('methodNotAllowed(["GET", "DELETE"])'));
    });

    test('a Void operation answers 204 and a TEXT one text', () {
      expect(router, contains('sendNoContent(res)'));
      expect(router, contains('sendText(res, result)'));
    });

    test('the entry point mounts the router and the resolvers keep only GraphQL operations', () {
      expect(_express(parser).serializeEntryPoint(), contains('app.use(buildRestRouter(services));'));
      final resolvers = _express(parser).serializeResolvers().first;
      expect(resolvers, contains('graphqlItem: '));
      expect(resolvers, isNot(contains('greeting: ')));
      expect(resolvers, isNot(contains('search: ')));
    });

    test('service methods of REST operations do not take the resolve info', () {
      final parser = _parse(_schema);
      final service = _express(parser).serializeService(parser.services['GreetingService']!);
      expect(service, isNot(contains('GraphQLResolveInfo')));
    });

    test('no router without REST operations', () {
      final plain = _parse('type Query { ping: Boolean! }');
      expect(_express(plain).hasRest, isFalse);
      expect(_express(plain).serializeEntryPoint(), isNot(contains('buildRestRouter')));
    });
  });

  group('uploads', () {
    test('Java MVC binds file parts as MultipartFile and text parts as request parameters', () {
      final out = _java('InfoServiceRestController', schema: _uploadSchema);
      expect(out, contains('@RequestPart(name = "file", required = true) MultipartFile file'));
      expect(out, contains('@RequestParam(name = "label", required = false) String label'));
      expect(out, contains('@RequestParam(name = "times", required = false) Integer times'));
      expect(out, contains('@RequestPart(name = "files", required = true) List<MultipartFile> files'));
      expect(out, contains('@RequestPart(name = "file", required = false) MultipartFile file'));
    });

    test('the service is called in its own argument order, which puts the upload last', () {
      final out = _java('InfoServiceRestController', schema: _uploadSchema);
      expect(out, contains('infoService.upload(label, times, file)'));
    });

    test('a raw body streams the servlet request', () {
      final out = _java('InfoServiceRestController', schema: _uploadSchema);
      expect(out, contains('HttpServletRequest __gl_request__'));
      expect(out, contains('GraphLinkRestUpload.rawFile(__gl_request__)'));
    });

    test('a controller with multipart parts answers a malformed envelope with 400 and an oversized one with 413', () {
      final out = _java('InfoServiceRestController', schema: _uploadSchema);
      expect(out, contains('@ExceptionHandler(MultipartException.class)'));
      expect(out, contains('@ResponseStatus(HttpStatus.BAD_REQUEST)'));
      expect(out, contains('@ExceptionHandler(MaxUploadSizeExceededException.class)'));
      expect(out, contains('@ResponseStatus(HttpStatus.PAYLOAD_TOO_LARGE)'));
    });

    test('WebFlux takes FilePart, checks the part kind, parses text parts itself and streams a raw body', () {
      final out = _java('InfoServiceRestController', reactive: true, schema: _uploadSchema);
      expect(out, contains('@RequestPart(name = "file", required = true) Part fileWire'));
      expect(out, contains('GraphLinkRest.filePart(fileWire)'));
      expect(out, contains('@RequestPart(name = "label", required = false) String labelWire'));
      expect(out, contains('Integer.valueOf(timesWire)'));
      expect(out, contains('@RequestBody(required = false) Flux<DataBuffer> __gl_body__'));
      expect(out, contains('@ExceptionHandler(DecodingException.class)'));
    });

    test('Kotlin binds the same parts', () {
      final out = _kotlin('InfoServiceRestController', schema: _uploadSchema);
      expect(out, contains('@RequestPart(name = "file", required = true) file: MultipartFile'));
      expect(out, contains('@RequestPart(name = "file", required = false) file: MultipartFile?'));
      expect(out, contains('__gl_request__: HttpServletRequest'));
      expect(out, contains('infoService.upload(label, times, file)'));
    });

    test('Express reads a multipart form once and takes each argument from it', () {
      final out = _express(_parse(_uploadSchema)).serializeRestRouter();
      expect(out, contains('const form = await readMultipart(req, res);'));
      expect(out, contains('fileArg(form, "file", {})'));
      expect(out, contains('fileArg(form, "file", { optional: true })'));
      expect(out, contains('fileListArg(form, "files", {})'));
      expect(out, contains('formArg(form, "label", S.string, { optional: true })'));
      expect(out, contains('rawUploadArg(req)'));
    });

    test('Express needs busboy only for multipart', () {
      final multipart = _express(_parse(_uploadSchema)).serializeRestUploads();
      expect(multipart, contains("import busboy from 'busboy';"));
      final rawOnly = _express(_parse('''
        directive @glUpload on SCALAR
        scalar Upload @glUpload
        type Query { ping: Boolean! }
        type Mutation { raw(file: Upload! @glRestBody): Boolean! @glRest(path: "/raw", method: PUT) }
      ''')).serializeRestUploads();
      expect(rawOnly, isNot(contains('busboy')));
      expect(rawOnly, contains('export function rawUploadArg'));
    });

    test('the GraphQL side knows nothing about an upload only REST uses', () {
      final parser = _parse(_uploadSchema);
      expect(parser.graphQLUsesUpload, isFalse);
      expect(GLGraphqlSerializer(parser).generateSchema(), isNot(contains('scalar Upload')));
      final entry = _express(parser).serializeEntryPoint();
      expect(entry, isNot(contains('graphqlUploadExpress')));
      expect(entry, isNot(contains('csrfPrevention')));
      expect(_express(parser).serializeResolvers().first, isNot(contains('GraphQLUpload')));
    });

    test('a GraphQL upload still wires the scalar', () {
      final parser = _parse('''
        directive @glUpload on SCALAR
        scalar Upload @glUpload
        type Query { ping: Boolean! }
        type Mutation { send(file: Upload!): Boolean! }
      ''');
      expect(parser.graphQLUsesUpload, isTrue);
      expect(GLGraphqlSerializer(parser).generateSchema(), contains('scalar Upload'));
    });
  });

  group('forms', () {
    const schema = '''
      enum Color { RED GREEN }
      type Echo { name: String! }
      type Query { ping: Boolean! }
      type Mutation {
        submit(name: String! @glRestField, qty: Int = 1 @glRestField, color: Color @glRestField, tags: [String!] @glRestField, note: String @glRestField(name: "memo")): Echo! @glRest(path: "/submit")
      }
    ''';

    test('Java MVC binds every field as a request parameter', () {
      final java = _java('EchoServiceRestController', schema: schema);
      expect(java, contains('@RequestParam(name = "name", required = true) String name'));
      expect(java, contains('@RequestParam(name = "qty", required = false, defaultValue = "1")'));
      expect(java, contains('@RequestParam(name = "memo", required = false) String note'));
      expect(java, contains('@RequestParam(name = "tags", required = false) List<String> tags'));
    });

    test('WebFlux reads the form off the exchange, since @RequestParam only sees the query string', () {
      final java = _java('EchoServiceRestController', schema: schema, reactive: true);
      expect(java, contains('ServerWebExchange __gl_exchange__'));
      expect(java, contains('return __gl_exchange__.getFormData().flatMap(__gl_form__ -> {'));
      expect(java, contains('GraphLinkRest.field(__gl_form__, "name", true)'));
      expect(java, contains('GraphLinkRest.field(__gl_form__, "qty", "1")'));
      expect(java, contains('GraphLinkRest.fields(__gl_form__, "tags", false)'));
    });

    test('Kotlin binds the fields like MVC', () {
      expect(_kotlin('EchoServiceRestController', schema: schema),
          contains('@RequestParam(name = "memo", required = false) note: String?'));
    });

    test('Express reads one decoded form', () {
      final router = _express(_parse(schema)).serializeRestRouter();
      expect(router, contains('const form = readForm(req)'));
      expect(router, contains('formArg(form, "name", S.string, {})'));
      expect(router, contains('formListArg(form, "tags", S.string, { optional: true })'));
      expect(router, contains("express.text({ type: 'application/x-www-form-urlencoded' })"));
    });
  });

  group('structured query and form values', () {
    const schema = '''
      input Address { city: String! }
      input Person { name: String! address: Address }
      input Line { sku: String! }
      type Out { ok: Boolean! }
      type Query {
        spread(person: Person @glRestParam): Out! @glRest(path: "/spread")
        flat(person: Person! @glRestParam(encoding: FLAT)): Out! @glRest(path: "/flat")
        lines(lines: [Line!]! @glRestParam): Out! @glRest(path: "/lines")
        json(person: Person @glRestParam(encoding: JSON)): Out! @glRest(path: "/json")
      }
      type Mutation {
        form(person: Person! @glRestField): Out! @glRest(path: "/form")
      }
    ''';

    test('Java MVC reads every parameter into one map and walks the shape of the input', () {
      final java = _java('OutServiceRestController', schema: schema);
      expect(java, contains('@RequestParam MultiValueMap<String, String> __gl_params__'));
      expect(java, contains('GraphLinkRestParams.nested(__gl_params__, "person", GraphLinkRestParams.Shape.obj()'));
      expect(java, contains('.field("address", "address", GraphLinkRestParams.Shape.obj()'));
      expect(java, contains('GraphLinkRestParams.json(__gl_params__, "person", false)'));
      expect(java, contains('GraphLinkRestParams.Shape.list('));
    });

    test('a spread input with a nested object is read from its shape with no prefix', () {
      final java = _java('OutServiceRestController', schema: schema);
      expect(java, contains('GraphLinkRestParams.nested(__gl_params__, "", GraphLinkRestParams.Shape.obj()'));
    });

    test('WebFlux reads the query string from the request and the form from the exchange', () {
      final java = _java('OutServiceRestController', schema: schema, reactive: true);
      expect(java, contains('MultiValueMap<String, String> __gl_query__ = __gl_exchange__.getRequest().getQueryParams()'));
      expect(java, contains('GraphLinkRestParams.nested(__gl_form__, "person"'));
    });

    test('Express reads them from the query parameters or the form fields and checks the shape', () {
      final router = _express(_parse(schema)).serializeRestRouter();
      expect(router, contains('const query = queryParams(req)'));
      expect(router, contains('nestedArg(query, "person"'));
      expect(router, contains('jsonArg(query, "person"'));
      expect(router, contains('nestedArg(form.fields, "person"'));
      expect(router, contains('nestedArg(query, "address"'));
    });

    test('the support class is only needed when an operation uses it', () {
      expect(_parse(schema).restUsesStructuredParams, isTrue);
      expect(_parse(_schema).restUsesStructuredParams, isFalse);
    });
  });

  group('downloads', () {
    const schema = '''
      scalar Download @glDownload
      type Query {
        file(name: String! @glRestParam): Download! @glRest(path: "/file")
        maybe: Download @glRest(path: "/maybe")
      }
    ''';

    test('Java MVC answers a ResponseEntity built from GraphLinkDownload', () {
      final java = _java('FileServiceRestController', schema: schema);
      expect(java, contains('public ResponseEntity<Resource> file('));
      expect(java, contains('return GraphLinkDownload.toResponse(fileService.file(name));'));
      expect(java, contains('import app.rest.GraphLinkDownload;'));
    });

    test('WebFlux maps the Mono and answers 204 for an empty one', () {
      final java = _java('FileServiceRestController', schema: schema, reactive: true);
      expect(java, contains('Mono<ResponseEntity<Resource>>'));
      expect(java, contains('.map(GraphLinkDownload::toResponse).defaultIfEmpty(GraphLinkDownload.toResponse(null))'));
    });

    test('Kotlin answers the same entity', () {
      expect(_kotlin('FileServiceRestController', schema: schema),
          contains('return GraphLinkDownload.toResponse(fileService.file(name))'));
    });

    test('the service takes and returns the GraphLinkDownload class', () {
      final parser = _parse(schema);
      final serializer = JavaSpringServerSerializer(parser, packageName: 'app', generateSchema: true);
      expect(serializer.serializeService(parser.services['FileService']!), contains('import app.rest.GraphLinkDownload;'));
    });

    test('Express sends it through sendDownload and the service type is imported', () {
      final parser = _parse(schema);
      final express = _express(parser);
      expect(express.serializeRestRouter(), contains('await sendDownload(res, result);'));
      expect(express.serializeService(parser.services['MaybeService']!), contains('Promise<GraphLinkDownload | null>'));
      expect(express.hasRestDownloads, isTrue);
    });

    test('the GraphQL schema has no Download scalar', () {
      expect(GLGraphqlSerializer(_parse(schema)).generateSchema(), isNot(contains('Download')));
    });
  });

  group('responsePath', () {
    const schema = '''
      type Item { id: ID! }
      type Query {
        items: [Item!]! @glRest(path: "/items", responsePath: "data.items")
        item: Item @glRest(path: "/item", responsePath: "result")
      }
    ''';

    test('the Java handler nests the converted value under the path', () {
      final java = _java('ItemServiceRestController', schema: schema);
      expect(java, contains('GraphLinkRest.wrap('));
      expect(java, contains('"data", "items")'));
    });

    test('WebFlux keeps the envelope when the Mono is empty', () {
      final java = _java('ItemServiceRestController', schema: schema, reactive: true);
      expect(java, contains('defaultIfEmpty(GraphLinkRest.wrap(null, "result"))'));
    });

    test('Express wraps what it sends', () {
      expect(_express(_parse(schema)).serializeRestRouter(), contains('["data", "items"])'));
    });
  });

  group('interceptors and the request context', () {
    const operationSchema = '''
      type Out { ok: Boolean! }
      type Query {
        guarded(name: String! @glRestParam): Out! @glIntercept(tag: "auth") @glRest(path: "/guarded")
        injected(name: String! @glRestParam): Out! @glInjectContext @glRest(path: "/injected")
        plain(name: String! @glRestParam): Out! @glRest(path: "/plain")
      }
    ''';
    const blockSchema = '''
      type Out { ok: Boolean! }
      extend type Query @glIntercept(tag: "auth") @glRestPrefix(path: "/b") {
        viaBlock(name: String! @glRestParam): Out! @glRest(path: "/x")
      }
    ''';

    test('an intercepted operation calls runBefore with its decoded arguments and a context built from the request', () {
      final java = _java('OutServiceRestController', schema: operationSchema);
      expect(java, contains('private final GraphLinkInterceptor interceptor;'));
      expect(java, contains('GraphLinkRest.context(__gl_request__)'));
      expect(java, contains('interceptor.runBefore(GlInterceptorTag.auth, "guarded", Arrays.asList(name), __gl_context__);'));
      expect(java, contains('outService.guarded(name, __gl_context__)'));
      expect(java, contains('outService.injected(name, __gl_context__)'));
      expect(java, contains('outService.plain(name)'));
    });

    test('a block level @glIntercept covers REST operations too', () {
      final java = _java('OutServiceRestController', schema: blockSchema);
      expect(java, contains('interceptor.runBefore(GlInterceptorTag.auth, "viaBlock"'));
    });

    test('WebFlux chains runBefore before the service call', () {
      final java = _java('OutServiceRestController', schema: blockSchema, reactive: true);
      expect(java, contains('interceptor.runBefore(GlInterceptorTag.auth, "viaBlock", Arrays.asList(name), __gl_context__).then(Mono.defer(() ->'));
      expect(java, contains('GraphLinkRest.context(__gl_exchange__)'));
    });

    test('Kotlin suspends and moves a blocking service to the IO dispatcher', () {
      final kotlin = _kotlin('OutServiceRestController', schema: blockSchema);
      expect(kotlin, contains('suspend fun viaBlock('));
      expect(kotlin, contains('interceptor.runBefore(GlInterceptorTag.auth, "viaBlock", listOf(name), __gl_context__)'));
      expect(kotlin, contains('withContext(Dispatchers.IO + SecurityCoroutineContext())'));
    });

    test('Express runs the interceptor after decoding the arguments', () {
      final router = _express(_parse(blockSchema)).serializeRestRouter();
      expect(router, contains('await services.interceptor!.runBefore(GlInterceptorTag.auth, "viaBlock", [name], context'));
      expect(router, contains('interceptor?: GraphLinkInterceptor'));
    });
  });

  group('operations the server does not support fail with a message', () {
    void rejects(String schema, String message) {
      expect(() => _parse(schema), throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
    }

    test('an input object as a multipart part', () {
      rejects('''
        input Meta { a: String }
        type Query { ping: Boolean! }
        type Mutation { send(meta: Meta! @glRestPart): Boolean! @glRest(path: "/send") }
      ''', 'an input object as a part');
    });

    test('a recursive input object in a query', () {
      rejects('''
        input Node { name: String next: Node }
        type Query { search(node: Node @glRestParam): Boolean! @glRest(path: "/search") }
      ''', 'a recursive input object');
    });

    test('a list of lists in a form', () {
      rejects('''
        type Query { ping: Boolean! }
        type Mutation { submit(grid: [[Int!]!]! @glRestField): Boolean! @glRest(path: "/submit") }
      ''', 'a list of lists');
    });
  });
}
