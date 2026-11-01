import 'package:graphlink/src/config.dart';
import 'package:test/test.dart';

const _required = {
  'dart': <String, dynamic>{},
  'java': {'packageName': 'a.b'},
  'typescript': <String, dynamic>{},
  'kotlin': {'packageName': 'a.b'},
  'swift': {'moduleName': 'M'},
  'python': <String, dynamic>{},
  'go': <String, dynamic>{},
};

ClientLanguageConfig _parse(String language, Map<String, dynamic> options) =>
    ClientLanguageConfig.fromJson({
      language: {..._required[language]!, ...options},
    });

Matcher _rejectsWith(String fragment) => throwsA(
    isA<ArgumentError>().having((e) => e.message.toString(), 'message', contains(fragment)));

void main() {
  for (final style in ['blocking', 'reactor', 'rxjava3', 'mutiny']) {
    test('java accepts apq with the $style style', () {
      final config = _parse('java', {'persistedQueries': 'apq', 'persistedQueriesUseGet': true, 'asyncStyle': style});
      expect(config.persistedQueries, PersistedQueriesMode.apq);
      expect(config.persistedQueriesUseGet, isTrue);
    });
  }

  for (final language in _required.keys) {
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
