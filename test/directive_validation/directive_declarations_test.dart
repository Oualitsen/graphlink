import 'dart:io';

import 'package:graphlink/src/model/internal_directive_declarations.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  final sdl = directiveDeclarationsForIde();

  test('declares every GraphLink directive', () {
    final declared = RegExp(r'^directive (@\w+)', multiLine: true).allMatches(sdl).map((m) => m.group(1)).toSet();
    expect(declared, containsAll(InternalDirectives.instance.definitions.keys.where((k) => k.startsWith('@gl'))));
  });

  test('leaves out the directives every GraphQL tool already knows', () {
    for (final standard in ['@include', '@skip', '@deprecated', '@specifiedBy']) {
      expect(sdl, isNot(contains('directive $standard')));
    }
  });

  test('is valid input for GraphLink itself', () {
    expect(() => GLParser().parse('$sdl\ntype Query { a: String }'), returnsNormally);
  });

  test('starts with a header saying where to put it', () {
    expect(sdl, startsWith('#'));
    expect(sdl, contains('schemaPaths'));
  });

  test('the documentation block is exactly the generated output', () {
    final doc = File('site/docs-src/directives.md').readAsStringSync();
    final start = doc.indexOf('```graphql title="directives.graphql"\n');
    expect(start, isNonNegative, reason: 'the copy-paste block is missing from directives.md');
    final body = doc.substring(start + '```graphql title="directives.graphql"\n'.length);
    expect(body.substring(0, body.indexOf('\n```')).trim(), sdl.trim());
  });
}
