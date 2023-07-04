import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

String serializeList(List<GQToken>? list,
    {String join = ", ", bool withParenthesis = true}) {
  return serializeListText(list?.map((e) => e.serialize()).toList(),
      withParenthesis: withParenthesis, join: join);
}

String serializeListText(List<String>? list,
    {String join = ", ", bool withParenthesis = true}) {
  if (list == null || list.isEmpty) {
    return '';
  }
  String result;
  if (withParenthesis) {
    result = "(${list.join(join)})";
  } else {
    result = list.join(join);
  }
  return result;
}

String formatUnformattedGraphQL(String unformattedGraphQL) {
  const indentSize = 2;
  var currentIndent = 0;
  var formattedGraphQL = '';

  final lines = unformattedGraphQL.split('\n');

  for (final line in lines) {
    final trimmedLine = line.trim();

    if (trimmedLine.isNotEmpty) {
      if (trimmedLine.startsWith('}')) {
        currentIndent -= indentSize;
      }

      formattedGraphQL += '${' ' * currentIndent}$trimmedLine\n';

      if (trimmedLine.endsWith('{')) {
        currentIndent += indentSize;
      }
    }
  }

  return formattedGraphQL.trim();
}

String? getNameValueFromDirectives(Iterable<GQDirectiveValue> directives) {
  var dirs = directives
      .where((element) => element.token == GQGrammar.gqTypeNameDirective);
  if (dirs.isEmpty) {
    return null;
  }
  var name = dirs.first.arguments
      .firstWhere(
          (arg) => arg.token == GQGrammar.gqTypeNameDirectiveArgumentName)
      .value as String;
  return name.replaceAll("\"", "");
}
