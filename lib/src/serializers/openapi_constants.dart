const swaggerUiVersion = '5.17.14';

String openApiDocsPage({required String title, required String specPath}) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escapeHtml(title.isEmpty ? 'API documentation' : title)}</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@$swaggerUiVersion/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@$swaggerUiVersion/swagger-ui-bundle.js"></script>
<script>
window.onload = function () {
  window.ui = SwaggerUIBundle({ url: ${_jsString(specPath)}, dom_id: '#swagger-ui' });
};
</script>
</body>
</html>
''';

String _escapeHtml(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _jsString(String text) =>
    "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('</', r'<\/')}'";
