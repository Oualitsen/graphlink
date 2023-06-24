import 'package:retrofit_graphql/graphql_parser/model/gq_token.dart';

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
