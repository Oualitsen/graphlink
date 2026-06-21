import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

/// Reproduces the `propagateFieldArgumentVariables` blow-up seen on the GitHub
/// schema, in miniature.
///
/// The shape that matters: a chain of interfaces (I0..I6), each implemented by
/// several concrete types, and every level has *multiple* fields pointing at the
/// next interface in the chain. With `generateAllFieldsFragments` + auto queries
/// the all-fields projection walks the whole graph; because the recursion fans
/// out to every implementation at each interface and re-walks every field with
/// no memoization, the number of recursive calls grows exponentially
/// (branching factor = fields-per-type x implementations-per-interface).
const schema = '''
interface I0 { id: String  a: I1  b: I1  c: I1 }
type A0 implements I0 { id: String  a: I1  b: I1  c: I1 }
type B0 implements I0 { id: String  a: I1  b: I1  c: I1 }
type C0 implements I0 { id: String  a: I1  b: I1  c: I1 }

interface I1 { id: String  a: I2  b: I2  c: I2 }
type A1 implements I1 { id: String  a: I2  b: I2  c: I2 }
type B1 implements I1 { id: String  a: I2  b: I2  c: I2 }
type C1 implements I1 { id: String  a: I2  b: I2  c: I2 }

interface I2 { id: String  a: I3  b: I3  c: I3 }
type A2 implements I2 { id: String  a: I3  b: I3  c: I3 }
type B2 implements I2 { id: String  a: I3  b: I3  c: I3 }
type C2 implements I2 { id: String  a: I3  b: I3  c: I3 }

interface I3 { id: String  a: I4  b: I4  c: I4 }
type A3 implements I3 { id: String  a: I4  b: I4  c: I4 }
type B3 implements I3 { id: String  a: I4  b: I4  c: I4 }
type C3 implements I3 { id: String  a: I4  b: I4  c: I4 }

interface I4 { id: String  a: I5  b: I5  c: I5 }
type A4 implements I4 { id: String  a: I5  b: I5  c: I5 }
type B4 implements I4 { id: String  a: I5  b: I5  c: I5 }
type C4 implements I4 { id: String  a: I5  b: I5  c: I5 }

interface I5 { id: String  a: I6  b: I6  c: I6 }
type A5 implements I5 { id: String  a: I6  b: I6  c: I6 }
type B5 implements I5 { id: String  a: I6  b: I6  c: I6 }
type C5 implements I5 { id: String  a: I6  b: I6  c: I6 }

interface I6 { id: String }
type A6 implements I6 { id: String }
type B6 implements I6 { id: String }
type C6 implements I6 { id: String }

type Query {
  root: I0
}
''';

void main() {
  test('propagateFieldArgumentVariables does not blow up on nested interfaces',
      () {
    final g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    final sw = Stopwatch()..start();
    g.parse(schema);
    sw.stop();

    expect(g.queries.isNotEmpty, true);
    // Before deduping the (type, selection-set) walk this took ~1.4s for this
    // tiny schema (2.4M recursive calls); with dedup it is a few ms. Guard
    // against the exponential regression returning.
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'propagateFieldArgumentVariables walk appears to be '
            're-exploding over the shared fragment DAG');
  });
}
