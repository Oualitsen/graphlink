import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/flutter_inputs/flutter_inputs_serializer.dart';
import 'package:test/test.dart';

const schema = '''
enum Role { ADMIN USER }
input AddressInput { street: String! }
input AccountInput { name: String! password: String! role: Role! address: AddressInput! }
type Query { x: String }
''';

class _Generated {
  final String form;
  final String sharedInputFormWidget;

  _Generated(this.form, this.sharedInputFormWidget);
}

_Generated _generate({required bool persistDrafts}) {
  final g = GLParser(naming: NamingConvention.dart, reservedWords: dartReservedWords)..parse(schema);
  final serializer = FlutterInputsSerializer(
    g,
    DartSerializer(g, importPrefix: ''),
    FlutterConfig(generateInputs: true, persistDrafts: persistDrafts),
    'pkg',
  );
  return _Generated(
    serializer.serializeInputForm(g.inputs['AccountInput']!),
    serializer.serializeSharedInputFormWidget(),
  );
}

void main() {
  test('nothing is generated unless persistDrafts is on', () {
    final out = _generate(persistDrafts: false);
    expect(out.form, isNot(contains('draftStore')));
    expect(out.form, isNot(contains('_restoring')));
    expect(out.sharedInputFormWidget, isNot(contains('restore(')));
  });

  group('persistDrafts', () {
    final out = _generate(persistDrafts: true);

    test('key is prefixed and built from the input name', () {
      expect(out.form, contains("static const draftKey = 'graphlink_generated_form_AccountInput';"));
      expect(out.form, contains('final FormDraftStore? draftStore;'));
      expect(out.form, contains('final String? draftId;'));
    });

    test('password-like fields are never saved or restored', () {
      expect(out.form, contains("m['name']"));
      expect(out.form, isNot(contains("m['password']")));
      expect(out.form, isNot(contains("draft['password']")));
    });

    test('nested forms get a path-derived draft id', () {
      expect(out.form, contains("draftId: _form.draftId == null ? 'address' : '\${_form.draftId}.address'"));
    });

    test('fields are disabled and read() refuses while restoring', () {
      expect(out.form, contains('!_submitting && !_restoring &&'));
      expect(out.form, contains("throw InputReadException('Form is restoring');"));
    });

    test('draft is flushed on dispose and cleared on full reset', () {
      expect(out.form, contains('_flushDraft();'));
      expect(out.form, contains('_clearDraft();'));
    });

    test('base state gets a restore hook', () {
      expect(out.sharedInputFormWidget, contains('void restore(T value) {}'));
    });
  });
}
