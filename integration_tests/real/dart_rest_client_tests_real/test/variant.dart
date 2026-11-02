import 'dart:io';

class Variant {
  final bool comma;
  final bool bracket;
  final String adapter;
  final int port;

  const Variant({required this.comma, required this.bracket, required this.adapter, required this.port});

  String key(String base, [List<Object> path = const []]) =>
      path.fold(base, (acc, p) => bracket ? '$acc[$p]' : '$acc.$p');

  List<String> list(String key, List<String> values) =>
      comma ? ['$key=${values.join(',')}'] : values.map((v) => '$key=$v').toList();
}

Variant _fromEnvironment() {
  switch (Platform.environment['REST_VARIANT']) {
    case 'dio':
      return const Variant(comma: true, bracket: true, adapter: 'dio', port: 9996);
    default:
      return const Variant(comma: false, bracket: false, adapter: 'http', port: 9995);
  }
}

final variant = _fromEnvironment();
