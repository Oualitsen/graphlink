import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

/// Regression tests for stack overflow in _createInlineExpandBlock.
///
/// Root cause: non-cyclic types inside _createInlineExpandBlock are never
/// depth-limited. Only types in cycleTypes decrement remainingDepth. So a
/// long chain of non-cyclic types (Link1→Link2→...→LinkN→Root) recurses N
/// frames before terminating, causing a stack overflow for large N.
///
/// The fix: track types visited on the current call path and break when a
/// type is seen again (path-based cycle detection).

/// Generates a schema with a long non-cyclic chain that eventually loops back
/// to a cyclic type. This is the exact pattern that caused the GitLab
/// schema stack overflow.
///
///   type Query { root: Root }
///   type Root { self: Root, chain: Link1 }   ← Root is cyclic (self-ref)
///   type Link1 { next: Link2 }
///   type Link2 { next: Link3 }
///   ...
///   type Link[N] { next: Root }              ← chain circles back to Root
///
/// Inside _createInlineExpandBlock(Root, depth=0, cycleTypes={Root}):
///   - self → Root is cyclic, depth=0 → null ✓
///   - chain → Link1 NOT cyclic, depth=0 (unchanged!) →
///       _createInlineExpandBlock(Link1, 0, {Root}) →
///         _createInlineExpandBlock(Link2, 0, {Root}) →
///           ... N frames ...
///           → Link[N].next = Root → cyclic, depth=0 → null
/// = N recursive calls → stack overflow for large N.
String _buildLongChainSchema(int chainLength) {
  final buf = StringBuffer('''
    type Query { root: Root }
    type Root {
      self: Root
      chain: Link1
      label: String
    }
  ''');
  for (var i = 1; i < chainLength; i++) {
    buf.writeln('type Link$i { next: Link${i + 1} value: String }');
  }
  buf.writeln('type Link$chainLength { next: Root value: String }');
  return buf.toString();
}

void main() {
  group('generateAllFieldsFragments — circular type references', () {
    test(
        'long non-cyclic chain back to cyclic root does not stack overflow',
        () {
      // 500 links is enough to overflow the Dart stack under the buggy code
      // (each link adds ~2 frames; Dart default stack is ~10k frames).
      final schema = _buildLongChainSchema(500);

      expect(
        () => GLParser(generateAllFieldsFragments: true).parse(schema),
        returnsNormally,
      );
    });
  });
}
