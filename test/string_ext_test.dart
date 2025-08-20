import 'package:retrofit_graphql/src/extensions.dart';
import 'package:test/test.dart';

void main() {
  test("test firstUp", () {
    expect("azul".firstUp, "Azul");
    expect("".firstUp, "");
  });

  test("test firstLow", () {
    expect("AZUL".firstLow, "aZUL");
    expect("".firstLow, "");
  });

  test("ident", () {
    expect("ident".ident(), "   ident");
    expect(
        """
line1
line2
"""
            .ident(),
        """
   line1
   line2
""");
  });

  test("remove quotes", () {
    expect(
        """
'''Hello'''
"""
            .removeQuotes(),
        "Hello");
    expect(
        '''
"""Hello"""
'''
            .removeQuotes(),
        "Hello");

    expect(
        """
'Hello'
"""
            .removeQuotes(),
        "Hello");

    expect(
        """
"Hello"
"""
            .removeQuotes(),
        "Hello");
  });

  test("test quote", () {
    expect("AZUL".quote(), "\"AZUL\"");
    expect("AZUL".quote(multiline: true), "\"\"\"AZUL\"\"\"");
  });

  test("test toJavaString", () {
    expect("AZUL".toJavaString(), "\"AZUL\"");
    expect(
        """
line1
line2
"""
            .toJavaString(),
        """
"line1\\n" + 
"line2"
"""
            .trim());
  });
}
