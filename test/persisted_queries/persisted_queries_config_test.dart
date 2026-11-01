import 'package:graphlink/src/config.dart';
import 'package:test/test.dart';

const _required = {
  'dart': <String, dynamic>{},
  'java': {'packageName': 'a.b'},
  'typescript': <String, dynamic>{},
  'kotlin': {'packageName': 'a.b'},
  'swift': {'moduleName': 'M'},
};

ClientLanguageConfig _parse(String language, Map<String, dynamic> options) =>
    ClientLanguageConfig.fromJson({
      language: {..._required[language]!, ...options},
    });

Matcher _rejectsWith(String fragment) => throwsA(
    isA<ArgumentError>().having((e) => e.message.toString(), 'message', contains(fragment)));

const _implemented = {'dart', 'typescript', 'kotlin', 'swift', 'java'};

void main() {
  for (final language in _required.keys.where((l) => !_implemented.contains(l))) {
    test('$language rejects apq until it is implemented', () {
      expect(
        () => _parse(language, {'persistedQueries': 'apq'}),
        _rejectsWith('not supported for $language yet'),
      );
    });
  }

  for (final style in ['reactor', 'rxjava3', 'mutiny']) {
    test('java with asyncStyle $style rejects apq until it is implemented', () {
      expect(
        () => _parse('java', {'persistedQueries': 'apq', 'asyncStyle': style}),
        _rejectsWith('not supported for java asyncStyle "$style" yet'),
      );
    });
  }

  test('java accepts apq with the blocking style', () {
    expect(_parse('java', {'persistedQueries': 'apq', 'asyncStyle': 'blocking'}).persistedQueries,
        PersistedQueriesMode.apq);
  });

  for (final language in _implemented) {
    group(language, () {
      test('persisted queries are off by default', () {
        final config = _parse(language, {});
        expect(config.persistedQueries, PersistedQueriesMode.off);
        expect(config.persistedQueriesUseGet, isFalse);
      });

      test('"apq" turns them on', () {
        expect(_parse(language, {'persistedQueries': 'apq'}).persistedQueries, PersistedQueriesMode.apq);
      });

      test('false is the same as leaving them off', () {
        expect(_parse(language, {'persistedQueries': false}).persistedQueries, PersistedQueriesMode.off);
      });

      test('GET can be enabled together with apq', () {
        final config = _parse(language, {'persistedQueries': 'apq', 'persistedQueriesUseGet': true});
        expect(config.persistedQueriesUseGet, isTrue);
      });

      test('an unknown mode is rejected, naming the valid ones', () {
        expect(() => _parse(language, {'persistedQueries': 'bogus'}), _rejectsWith('false or "apq"'));
        expect(() => _parse(language, {'persistedQueries': true}), _rejectsWith('false or "apq"'));
        expect(() => _parse(language, {'persistedQueries': 'manifest'}), _rejectsWith('false or "apq"'));
      });

      test('GET without apq is rejected instead of silently ignored', () {
        expect(
          () => _parse(language, {'persistedQueriesUseGet': true}),
          _rejectsWith('persistedQueriesUseGet requires persistedQueries'),
        );
      });
    });
  }
}
