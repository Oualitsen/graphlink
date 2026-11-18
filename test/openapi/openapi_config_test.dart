import 'package:graphlink/src/config.dart';
import 'package:test/test.dart';

ServerConfig _server(Map<String, dynamic> extra) => ServerConfig.fromJson({
      'expressApollo': <String, dynamic>{},
      ...extra,
    });

void main() {
  test('no openapi section means no config', () {
    expect(_server({}).openApi, isNull);
  });

  test('defaults when the section is empty', () {
    final c = _server({'openapi': <String, dynamic>{}}).openApi!;
    expect(c.file, isNull);
    expect(c.serve, isTrue);
    expect(c.specPath, '/openapi.json');
    expect(c.docsPath, '/docs');
    expect(c.title, '');
    expect(c.version, '0.0.0');
    expect(c.serverUrl, '/');
  });

  test('every key is read', () {
    final c = _server({
      'openapi': {
        'file': 'api.json',
        'serve': false,
        'specPath': '/spec',
        'docsPath': '/explorer',
        'title': 'My API',
        'version': '1.2.3',
        'serverUrl': '/api',
      },
    }).openApi!;
    expect(c.file, 'api.json');
    expect(c.serve, isFalse);
    expect(c.specPath, '/spec');
    expect(c.docsPath, '/explorer');
    expect(c.title, 'My API');
    expect(c.version, '1.2.3');
    expect(c.serverUrl, '/api');
  });

  test('works next to every server flavor', () {
    for (final language in ['expressApollo', 'nestApollo']) {
      final c = ServerConfig.fromJson({language: <String, dynamic>{}, 'openapi': <String, dynamic>{}});
      expect(c.openApi, isNotNull, reason: language);
    }
  });

  test('rejects bad values', () {
    for (final bad in <Object?>[
      'yes',
      {'serve': 'yes'},
      {'file': ''},
      {'specPath': 'openapi.json'},
      {'docsPath': 3},
      {'title': 1},
      {'specPath': '/x', 'docsPath': '/x'},
    ]) {
      expect(() => _server({'openapi': bad}), throwsA(isA<ArgumentError>()), reason: '$bad');
    }
  });
}
