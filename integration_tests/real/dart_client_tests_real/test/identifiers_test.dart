import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  Map<String, String> fieldsOf(Reserved r) => {
        'type': r.type, 'default': r.default_, 'in': r.in_, 'is': r.is_, 'var': r.var_, 'val': r.val,
        'fun': r.fun, 'new': r.new_, 'import': r.import_, 'return': r.return_, 'object': r.object,
        'from': r.from, 'None': r.none, 'True': r.true_, 'func': r.func, 'range': r.range,
        'self': r.self, 'Self': r.self2, 'init': r.init, 'Type': r.type2, 'Protocol': r.protocol,
        'async': r.async, 'await': r.await_, 'package': r.package, 'interface': r.interface_,
        'enum': r.enum_, 'null': r.null_,
      };

  void expectEchoed(Map<String, String> fields) {
    expect(fields, hasLength(27));
    fields.forEach((wire, value) => expect(value, 'v:$wire', reason: wire));
  }

  group('reserved words', () {
    test('as argument names', () async {
      final r = (await client.queries.reservedEcho(
        type: 'v:type', default_: 'v:default', in_: 'v:in', is_: 'v:is', var_: 'v:var', val: 'v:val',
        fun: 'v:fun', new_: 'v:new', import_: 'v:import', return_: 'v:return', object: 'v:object',
        from: 'v:from', none: 'v:None', true_: 'v:True', func: 'v:func', range: 'v:range',
        self: 'v:self', self2: 'v:Self', init: 'v:init', type2: 'v:Type', protocol: 'v:Protocol',
        async: 'v:async', await_: 'v:await', package: 'v:package', interface_: 'v:interface',
        enum_: 'v:enum', null_: 'v:null',
      )).reservedEcho;
      expectEchoed(fieldsOf(r));
    });

    test('as input fields and response fields', () async {
      final r = (await client.queries.reservedEchoInput(
        input: ReservedInput(
          type: 'v:type', default_: 'v:default', in_: 'v:in', is_: 'v:is', var_: 'v:var', val: 'v:val',
          fun: 'v:fun', new_: 'v:new', import_: 'v:import', return_: 'v:return', object: 'v:object',
          from: 'v:from', none: 'v:None', true_: 'v:True', func: 'v:func', range: 'v:range',
          self: 'v:self', self2: 'v:Self', init: 'v:init', type2: 'v:Type', protocol: 'v:Protocol',
          async: 'v:async', await_: 'v:await', package: 'v:package', interface_: 'v:interface',
          enum_: 'v:enum', null_: 'v:null',
        ),
      )).reservedEchoInput;
      expectEchoed(fieldsOf(r));
    });

    test('as operation names', () async {
      expect((await client.queries.import_(value: 'a')).import_, 'a');
      expect((await client.queries.default_(value: 'b')).default_, 'b');
      expect((await client.queries.new_(value: 'c')).new_, 'c');
      expect((await client.queries.func(value: 'd')).func, 'd');
      expect((await client.queries.none(value: 'e')).none, 'e');
      expect((await client.queries.self(value: 'f')).self, 'f');
    });
  });

  group('enum values that look like literals or keywords', () {
    test('every value decodes', () async {
      final all = (await client.queries.literals()).literals;
      expect(all, [
        Literal.default_, Literal.class_, Literal.none, Literal.true_,
        Literal.nil, Literal.undefined, Literal.naN, Literal.self,
      ]);
    });

    test('every value round trips as an argument', () async {
      final values = Literal.values.where((v) => v != Literal.unknownValue__).toList();
      for (final v in values) {
        expect((await client.queries.literalEcho(v: v, all: values)).literalEcho, v);
      }
    });
  });

  group('type names that clash with the standard library', () {
    test('all decode', () async {
      final c = (await client.queries.clashes()).clashes;
      expect(c.error.id, 'error-1');
      expect(c.response.id, 'response-1');
      expect(c.request.id, 'request-1');
      expect(c.list.id, 'list-1');
      expect(c.map.id, 'map-1');
      expect(c.object.id, 'object-1');
      expect(c.optional.id, 'optional-1');
      expect(c.date.id, 'date-1');
      expect(c.result.id, 'result-1');
      expect(c.void_.id, 'void-1');
    });
  });

  group('names that collide after normalisation or look odd', () {
    test('every field round trips', () async {
      final r = (await client.queries.oddEcho(
        input: const OddInput(
          userId2: 'user_id', userId: 'userId', urlValue: 'URLValue', httpServer: 'HTTPServer',
          leading: '_leading', trailing: 'trailing_', v2Name: 'v2_name', isActive: 'isActive',
          active: 'active', getX: 'getX', x: 'x',
        ),
      )).oddEcho;
      expect([r.userId2, r.userId, r.urlValue, r.httpServer, r.leading, r.trailing, r.v2Name, r.isActive, r.active, r.getX, r.x],
          ['user_id', 'userId', 'URLValue', 'HTTPServer', '_leading', 'trailing_', 'v2_name', 'isActive', 'active', 'getX', 'x']);
    });
  });
}
