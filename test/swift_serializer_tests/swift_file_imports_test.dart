import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/swift_serializer.dart';
import 'package:test/test.dart';

SwiftSerializer _serializer(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');

void main() {
  group('getFileNameFor', () {
    test('uses the type\'s codeName with a .swift extension', () {
      final g = GLParser()..parse('type User { id: ID! }');
      final token = g.types['User']!;
      expect(_serializer(g).getFileNameFor(token), 'User.swift');
    });
  });

  group('serializeImportToken', () {
    test('always returns empty — same-module types need no import', () {
      final g = GLParser()..parse('''
        type Address { city: String! }
        type User { id: ID! address: Address }
      ''');
      final addressToken = g.types['Address']!;
      expect(_serializer(g).serializeImportToken(addressToken), '');
    });
  });

  group('serializeImport', () {
    test('renders a plain `import X` line for a free-form import string', () {
      final g = GLParser()..parse('type User { id: ID! }');
      expect(_serializer(g).serializeImport('Foundation'), 'import Foundation');
    });
  });

  group('serializeGlClass', () {
    late GLParser g;
    setUp(() {
      g = GLParser()..parse('type User { id: ID! }');
    });

    test('cross-type importDepencies contribute nothing to the output', () {
      final addressToken = g.types['User']!; // any GLToken works as a stand-in dependency
      final model = GLClassModel(
        importDepencies: [addressToken],
        body: 'public struct User {}',
      );
      final out = _serializer(g).serializeGlClass(model);
      expect(out, isNot(contains('import')));
      expect(out.trim(), 'public struct User {}');
    });

    test('genuine free-form imports still render, deduplicated', () {
      final model = GLClassModel(
        imports: const ['Foundation', 'Foundation'],
        body: 'public struct User {}',
      );
      final out = _serializer(g).serializeGlClass(model);
      expect('import Foundation'.allMatches(out).length, 1);
    });

    test('withImports: false returns only the trimmed body', () {
      final model = GLClassModel(
        imports: const ['Foundation'],
        body: '  public struct User {}  ',
      );
      final out = _serializer(g).serializeGlClass(model, withImports: false);
      expect(out, 'public struct User {}');
    });
  });
}
